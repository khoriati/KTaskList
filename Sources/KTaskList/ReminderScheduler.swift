import AppKit
import Combine
import SwiftUI

/// Dispara os alertas de lembrete.
///
/// - Lembretes **com horário** são verificados por timer.
/// - Lembretes **só do dia** são apresentados apenas nas "oportunidades": abertura
///   do app, login/troca de usuário, desbloqueio da tela ou wake.
/// - Dispensar (OK / fechar a janela) só esconde o alerta até a próxima
///   oportunidade: enquanto a tarefa não for concluída (ou o lembrete removido),
///   todo lembrete vencido volta a ser exibido em cada uma delas.
@MainActor
final class ReminderScheduler: ObservableObject {
    enum Trigger {
        case launch, timer, session
        var includesAllDay: Bool { self != .timer }
    }

    /// Ids das tarefas atualmente exibidas na janela de alerta.
    @Published private(set) var presentedIDs: [UUID] = []

    private let store: TaskStore
    private let alertWindow = ReminderAlertWindow()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var cancellable: AnyCancellable?

    init(store: TaskStore) {
        self.store = store
        alertWindow.onClose = { [weak self] in self?.dismissAll() }

        cancellable = store.$tasks.sink { [weak self] tasks in
            self?.prune(using: tasks)
        }

        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.check(.timer) }
        }
        timer.tolerance = 5
        // Modo .common: continua disparando com menus abertos, arrasto ou painel modal.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let workspace = NSWorkspace.shared.notificationCenter
        let sessionEvents: [Notification.Name] = [
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
        ]
        for name in sessionEvents {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.check(.session) }
            })
        }
        // Notificação distribuída não documentada pela Apple, mas estável há anos; é a
        // única forma de saber do desbloqueio da tela sem permissões especiais.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.check(.session) }
        })

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.check(.launch)
        }
    }

    deinit {
        timer?.invalidate()
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        for observer in observers {
            workspace.removeObserver(observer)
            distributed.removeObserver(observer)
        }
    }

    // MARK: - Verificação

    func check(_ trigger: Trigger) {
        let now = Date()
        let due: [TaskItem]
        if trigger.includesAllDay {
            // Oportunidade de sessão: reexibe tudo o que está vencido, mesmo já dispensado.
            due = store.allTasks.filter { task in
                guard let reminder = task.reminder, !task.isDone else { return false }
                return reminder.fireDate <= now
            }
        } else {
            due = store.allTasks.filter { task in
                guard let reminder = task.reminder, task.hasOverdueReminder(at: now) else { return false }
                return reminder.hasTime
            }
        }
        let new = due.map(\.id).filter { !presentedIDs.contains($0) }
        guard !new.isEmpty else { return }
        // Reativa os dispensados para que voltem a contar como pendentes na janela.
        for id in new where store.find(id)?.reminder?.isPending == false {
            store.update(id) { $0.reminder?.acknowledgedAt = nil }
        }
        presentedIDs.append(contentsOf: new)
        alertWindow.present(store: store, scheduler: self)
        NSSound(named: "Glass")?.play()
    }

    /// Remove da janela o que deixou de estar vencido (dispensado, adiado, concluído, excluído).
    private func prune(using tasks: [TaskItem]) {
        let now = Date()
        let all = tasks.flattened
        let remaining = presentedIDs.filter { id in
            all.first { $0.id == id }?.hasOverdueReminder(at: now) ?? false
        }
        guard remaining != presentedIDs else { return }
        presentedIDs = remaining
        if remaining.isEmpty { alertWindow.close() }
    }

    // MARK: - Ações do alerta

    func acknowledge(_ id: UUID) {
        store.acknowledgeReminder(id)
    }

    func snooze(_ id: UUID, by interval: TimeInterval) {
        store.snoozeReminder(id, until: Date().addingTimeInterval(interval))
    }

    func snoozeUntilTomorrowMorning(_ id: UUID) {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        let at9 = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        store.snoozeReminder(id, until: at9)
    }

    func complete(_ id: UUID) {
        store.markDone(id)
    }

    func open(_ id: UUID) {
        guard let route = store.route(for: id) else { return }
        store.acknowledgeReminder(id)
        TaskWindows.shared.open(route: route, store: store)
    }

    /// Fechar a janela pelo botão vermelho equivale a dispensar tudo.
    func dismissAll() {
        presentedIDs.forEach(store.acknowledgeReminder)
    }
}

// MARK: - Janela de alerta

/// Janela flutuante que lista os lembretes vencidos. Não usa notificações do
/// sistema (que exigem permissão e bundle assinado) — é uma janela própria.
@MainActor
final class ReminderAlertWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var isClosingProgrammatically = false
    var onClose: (() -> Void)?

    func present(store: TaskStore, scheduler: ReminderScheduler) {
        if window == nil {
            let view = ReminderAlertView()
                .environmentObject(store)
                .environmentObject(scheduler)
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            w.title = "Lembretes"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            w.minSize = NSSize(width: 360, height: 220)
            w.contentView = NSHostingView(rootView: view)
            w.delegate = self
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        guard let window, window.isVisible, !isClosingByUser else { return }
        isClosingProgrammatically = true
        window.close()
        isClosingProgrammatically = false
    }

    /// Evita `close()` reentrante: `onClose` → dispensar → `prune` → `close()` enquanto
    /// a janela ainda está em `windowWillClose`.
    private var isClosingByUser = false

    func windowWillClose(_ notification: Notification) {
        guard !isClosingProgrammatically else { return }
        isClosingByUser = true
        onClose?()
        isClosingByUser = false
    }
}

// MARK: - Coordenação popover x janelas destacadas

/// Popover da barra de menu e janelas destacadas são mutuamente exclusivos:
/// destacar fecha o popover; abrir o popover fecha as janelas destacadas.
@MainActor
enum DetachedWindows {
    static let sceneID = "main"

    static func isDetached(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == sceneID || TaskWindows.shared.owns(window)
    }

    static func closeAll() {
        NSApp.windows.filter(isDetached).forEach { $0.close() }
    }
}

// MARK: - Janelas avulsas de tarefa

/// Abre a tarefa em uma janela comum (usado pelo alerta, que não vive em uma
/// cena SwiftUI e por isso não tem acesso a `openWindow`).
@MainActor
final class TaskWindows: NSObject, NSWindowDelegate {
    static let shared = TaskWindows()
    private var windows: [NSWindow] = []

    func open(route: Route?, store: TaskStore) {
        let view = RootView(initialPath: route.map { [$0] } ?? [])
            .environmentObject(store)
            .environmentObject(store.settings)
            .environment(\.isDetachedWindow, true)
            .frame(minWidth: 560, minHeight: 440)
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        w.title = "Tarefas"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.delegate = self
        w.center()
        windows.append(w)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func owns(_ window: NSWindow) -> Bool {
        windows.contains { $0 === window }
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === w }
    }
}
