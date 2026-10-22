import ServiceManagement
import SwiftUI

/// Indica que a view está em uma janela destacada (não no popover da barra de menu).
private struct DetachedWindowKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isDetachedWindow: Bool {
        get { self[DetachedWindowKey.self] }
        set { self[DetachedWindowKey.self] = newValue }
    }
}

/// Tela inicial: cabeçalho, criação rápida, mapa mental ou lista, rodapé.
struct HomeView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.isDetachedWindow) private var isDetached
    @Binding var path: [Route]

    @State private var newTitle = ""
    @State private var confirmation: InlineConfirmation?
    @FocusState private var newTitleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            quickAdd
            filterBar
            Divider()
            content
            Divider()
            footer
        }
        .onAppear { newTitleFocused = true }
        .inlineConfirmation($confirmation)
    }

    // MARK: - Confirmações

    private func askClearCompleted() {
        confirmation = InlineConfirmation(
            title: "Remover \(store.doneCount) item(ns) concluído(s)?",
            message: "Sub-itens e anexos desses itens também serão apagados.",
            actionLabel: "Remover"
        ) { store.clearCompleted() }
    }

    func askDelete(_ task: TaskItem) {
        let extra = task.subtasks.isEmpty ? "Os anexos também serão apagados." : "Sub-itens e anexos também serão apagados."
        confirmation = InlineConfirmation(
            title: "Excluir \"\(task.title)\"?",
            message: extra
        ) { store.deleteTask(id: task.id) }
    }

    // MARK: - Seções

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist").foregroundStyle(.tint)
            Text("Tarefas").font(.headline)
            Spacer()

            Picker("Visualização", selection: $settings.viewMode) {
                ForEach(AppSettings.ViewMode.allCases) { mode in
                    Image(systemName: mode.systemImage).help(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if !isDetached {
                Button(action: detach) {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Destacar em uma janela")
            }

            Menu {
                if !isDetached {
                    Button("Destacar em janela", action: detach)
                }
                SettingsLink { Text("Configurações…") }
                Button("Mostrar pasta de dados") { store.revealDataFolder() }
                Divider()
                Toggle("Mostrar concluídas", isOn: $settings.showCompleted)
                LaunchAtLoginToggle()
                Divider()
                Button("Expandir tudo") { settings.collapsedIDs.removeAll() }
                    .disabled(settings.collapsedIDs.isEmpty)
                Button("Limpar concluídas…", action: askClearCompleted)
                    .disabled(store.doneCount == 0)
                Divider()
                Button("Sair") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Abre a janela destacada e fecha o popover da barra de menu.
    private func detach() {
        let popover = NSApp.keyWindow
        openWindow(id: DetachedWindows.sceneID)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            if let popover, !DetachedWindows.isDetached(popover) { popover.close() }
        }
    }

    private var quickAdd: some View {
        HStack(spacing: 8) {
            TextField("Novo item raiz…", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .focused($newTitleFocused)
                .onSubmit(addTask)
            Button(action: addTask) {
                Image(systemName: "plus.circle.fill").imageScale(.large)
            }
            .buttonStyle(.plain)
            .foregroundStyle(newTitle.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : Color.accentColor)
            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    /// Filtros rápidos: pendentes, concluídas e atrasadas.
    private var filterBar: some View {
        HStack(spacing: 6) {
            FilterChip(title: "Pendentes", systemImage: "circle", count: store.pendingCount,
                       isOn: $settings.showPending)
            FilterChip(title: "Concluídas", systemImage: "checkmark.circle", count: store.doneCount,
                       isOn: $settings.showCompleted)
            FilterChip(title: "Atrasadas", systemImage: "clock.badge.exclamationmark", count: store.lateCount,
                       isOn: $settings.onlyLate, tint: .red)
            Spacer()
            if !settings.showPending || !settings.showCompleted || settings.onlyLate {
                Button("Limpar") {
                    settings.showPending = true
                    settings.showCompleted = true
                    settings.onlyLate = false
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if store.tasks.isEmpty {
            ContentUnavailableView {
                Label("Nenhum item", systemImage: "tray")
            } description: {
                Text("Digite acima e pressione Enter para criar o primeiro.")
            }
            .frame(maxHeight: .infinity)
        } else if visibleRoots.isEmpty {
            ContentUnavailableView {
                Label(emptyFilterTitle, systemImage: settings.onlyLate ? "clock.badge.checkmark" : "line.3.horizontal.decrease.circle")
            } description: {
                Text(emptyFilterDescription)
            }
            .frame(maxHeight: .infinity)
        } else {
            switch settings.viewMode {
            case .map:
                MindMapCanvasView(roots: visibleRoots, path: $path, askDelete: askDelete)
            case .list:
                TaskOutlineView(roots: visibleRoots, path: $path, askDelete: askDelete)
            }
        }
    }

    private var emptyFilterTitle: String {
        if !settings.showPending && !settings.showCompleted { return "Nenhum filtro ativo" }
        if settings.onlyLate { return "Nenhum item atrasado" }
        return settings.showPending ? "Tudo concluído" : "Nada concluído ainda"
    }

    /// Explica quais filtros estão restringindo o resultado.
    private var emptyFilterDescription: String {
        if !settings.showPending && !settings.showCompleted {
            return "Pendentes e Concluídas estão desligados, então nada é exibido. Ligue pelo menos um deles."
        }
        var scope: [String] = []
        if !settings.showPending { scope.append("pendentes ocultos") }
        if !settings.showCompleted { scope.append("concluídos ocultos") }
        if settings.onlyLate {
            if store.lateCount > 0, !scope.isEmpty {
                return "Existem \(store.lateCount) atrasado(s), mas estão fora do filtro (\(scope.joined(separator: ", "))). Ajuste os filtros acima."
            }
            return scope.isEmpty
                ? "Nenhum item aberto passou do planejado."
                : "Considerando só o que está visível (\(scope.joined(separator: ", ")))."
        }
        return scope.isEmpty
            ? "Ajuste os filtros rápidos acima para ver os itens."
            : "Filtro atual: \(scope.joined(separator: ", ")). Ajuste os filtros acima."
    }

    /// Floresta exibida conforme os filtros rápidos.
    private var visibleRoots: [TaskItem] {
        if settings.showPending && settings.showCompleted && !settings.onlyLate { return store.tasks }
        let now = Date()
        return store.tasks.filtered { settings.matchesFilter($0, now: now) }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(store.pendingCount) pendente(s) · \(store.doneCount) concluída(s)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if store.lateCount > 0 {
                Button { settings.onlyLate.toggle() } label: {
                    Label("\(store.lateCount) atrasado(s)", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .underline(settings.onlyLate)
                }
                .buttonStyle(.plain)
                .help(settings.onlyLate ? "Mostrar todos" : "Mostrar só os atrasados")
            }
            Spacer()
            if settings.viewMode == .map {
                zoomControls
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button { settings.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
                .disabled(settings.mapZoom <= AppSettings.zoomRange.lowerBound + 0.001)
            Button { settings.resetZoom() } label: {
                Text("\(Int((settings.mapZoom * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 38)
            }
            .help("Restaurar zoom (100%)")
            Button { settings.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
                .disabled(settings.mapZoom >= AppSettings.zoomRange.upperBound - 0.001)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    private func addTask() {
        guard store.addTask(title: newTitle) != nil else { return }
        newTitle = ""
        newTitleFocused = true
    }
}

// MARK: - Filtro rápido

/// Botão-toggle compacto da barra de filtros, com contador.
private struct FilterChip: View {
    let title: String
    let systemImage: String
    let count: Int
    @Binding var isOn: Bool
    var tint: Color = .accentColor

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
            }
            .font(.caption)
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(tint)
    }
}

// MARK: - Iniciar com o login

private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Iniciar com o login", isOn: $enabled)
            .onChange(of: enabled) { _, newValue in
                do {
                    if newValue { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
    }
}
