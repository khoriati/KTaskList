import SwiftUI

@main
struct KTaskListApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var store: TaskStore
    @StateObject private var scheduler: ReminderScheduler

    init() {
        let settings = AppSettings()
        let store = TaskStore(settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: store)
        _scheduler = StateObject(wrappedValue: ReminderScheduler(store: store))
        // KTASKLIST_OPEN_WINDOW=1 abre a janela destacada já no início (testes manuais);
        // com o id de um item, abre direto no detalhe dele.
        if let flag = ProcessInfo.processInfo.environment["KTASKLIST_OPEN_WINDOW"], !flag.isEmpty {
            let route = UUID(uuidString: flag).flatMap { store.route(for: $0) }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                TaskWindows.shared.open(route: route, store: store)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .frame(width: 520, height: 620)
                // Abrir o popover recolhe as janelas destacadas (e vice-versa, em HomeView.detach).
                // Como o app é "accessory" (LSUIElement), o painel da barra de menu não
                // ativa o app sozinho; sem ativação os campos de texto não recebem teclado.
                .onAppear {
                    DetachedWindows.closeAll()
                    NSApp.activate(ignoringOtherApps: true)
                }
        } label: {
            Image(systemName: scheduler.presentedIDs.isEmpty ? "checklist" : "bell.badge")
            if store.pendingCount > 0 {
                Text("\(store.pendingCount)")
            }
        }
        .menuBarExtraStyle(.window)

        Window("Tarefas", id: DetachedWindows.sceneID) {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .environment(\.isDetachedWindow, true)
                .frame(minWidth: 560, minHeight: 440)
        }
        .defaultSize(width: 980, height: 700)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(settings)
        }
    }
}

/// Rotas de navegação dentro do popover / janela.
enum Route: Hashable {
    /// Detalhe de um item em qualquer nível.
    case detail(UUID)
}

struct RootView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var path: [Route]

    init(initialPath: [Route] = []) {
        _path = State(initialValue: initialPath)
    }

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
        .toolbar(.hidden, for: .windowToolbar)
        .background(.background)
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .detail(let id):
            if let binding = store.binding(for: id) {
                TaskDetailView(task: binding, path: $path)
            } else {
                MissingView(path: $path)
            }
        }
    }
}

private struct MissingView: View {
    @Binding var path: [Route]
    var body: some View {
        ContentUnavailableView("Item removido", systemImage: "trash")
            .onAppear { path.removeAll() }
    }
}
