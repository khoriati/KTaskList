import SwiftUI
import UniformTypeIdentifiers

/// Mapa mental dos itens: cards com conectores, criação de sub-itens no hover,
/// arrastar-e-soltar para mover entre árvores, recolher/expandir e teclado.
struct MindMapCanvasView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var settings: AppSettings
    let roots: [TaskItem]
    @Binding var path: [Route]
    let askDelete: (TaskItem) -> Void

    @State private var hoveredID: UUID?
    @State private var selectedID: UUID?
    @State private var editingID: UUID?
    @State private var draggingID: UUID?
    @State private var backgroundTargeted = false
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @FocusState private var canvasFocused: Bool

    private let metrics = MindMapMetrics.default

    private var layout: MindMapLayout {
        MindMapLayout.compute(roots: roots, metrics: metrics, collapsed: settings.collapsedIDs)
    }

    var body: some View {
        let layout = layout
        let zoom = settings.mapZoom
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { deselect() }
                ConnectorsView(edges: layout.edges)
                    .allowsHitTesting(false)
                ForEach(layout.nodes) { node in
                    card(for: node)
                        .frame(width: metrics.cardWidth + metrics.trailingControls, height: metrics.cardHeight)
                        .position(x: node.frame.midX + metrics.trailingControls / 2, y: node.frame.midY)
                }
            }
            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
            .scaleEffect(zoom, anchor: .topLeading)
            .frame(width: layout.size.width * zoom, height: layout.size.height * zoom, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                    .padding(6)
            )
            .onDrop(of: [.text], isTargeted: $backgroundTargeted) { providers in
                handleDrop(providers, target: .root)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .focusable()
        .focusEffectDisabled()
        .focused($canvasFocused)
        .onKeyPress(.tab) { addChildToSelected() }
        .onKeyPress(.return) { addSiblingToSelected() }
        .onKeyPress(.space) { toggleSelectedDone() }
        .onKeyPress(.escape) { editingID == nil ? deselect() : .ignored }
        .onKeyPress(.delete) { deleteSelected() }
        .onKeyPress(.deleteForward) { deleteSelected() }
        .onKeyPress(characters: .init(charactersIn: "oO")) { _ in openSelected() }
        .overlay(alignment: .bottom) { toastView }
        .overlay(alignment: .topTrailing) { hint }
        .onChange(of: layout.nodes.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
            if let editingID, !ids.contains(editingID) { self.editingID = nil }
        }
        .onDisappear {
            discardEmptyDrafts()
            toastTask?.cancel()
        }
    }

    // MARK: - Card

    @ViewBuilder
    private func card(for node: MindMapLayout.Node) -> some View {
        let isDragging = draggingID == node.id
        TaskCardView(
            node: node,
            color: MindMapPalette.color(for: node.rootIndex),
            isSelected: selectedID == node.id,
            isHovered: hoveredID == node.id,
            isEditing: editingID == node.id || store.draftIDs.contains(node.id),
            canAddChild: store.canAddChild(to: node.id),
            maxSubLevels: settings.maxSubLevels,
            dropCheck: { zone in
                draggingID.map { dragged in
                    zone == .child ? store.canMove(dragged, toParent: node.id)
                                   : store.canMove(dragged, besides: node.id)
                }
            },
            onHover: { hovering in
                hoveredID = hovering ? node.id : (hoveredID == node.id ? nil : hoveredID)
                // Hover só volta a chegar depois que a sessão de arrasto termina: se ainda
                // há um `draggingID`, o arrasto foi cancelado (soltura fora de alvo, Esc).
                if hovering, draggingID != nil { draggingID = nil }
            },
            onSelect: { select(node.id) },
            onOpen: { open(node.id) },
            onToggleDone: { store.toggleDone(id: node.id) },
            onAddChild: { addChild(to: node.id) },
            onToggleCollapse: { settings.toggleCollapsed(node.id) },
            onCommitTitle: { title in
                store.commitTitle(node.id, title)
                editingID = nil
                canvasFocused = true
            },
            onCancelEdit: {
                store.discardDraft(node.id)
                editingID = nil
                canvasFocused = true
            },
            onDragStart: {
                draggingID = node.id
                return NSItemProvider(object: node.id.uuidString as NSString)
            },
            onDrop: { providers, zone in handleDrop(providers, target: .card(node.id, zone)) }
        )
        .opacity(isDragging ? 0.5 : 1)
        .contextMenu { contextMenu(for: node) }
        .zIndex(selectedID == node.id || hoveredID == node.id ? 1 : 0)
    }

    @ViewBuilder
    private func contextMenu(for node: MindMapLayout.Node) -> some View {
        let item = node.item
        Button("Abrir") { open(item.id) }
        Button("Renomear") { startEditing(item.id) }
        Button(item.isDone ? "Reabrir" : "Concluir") { store.toggleDone(id: item.id) }
        Divider()
        Button("Novo sub-item") { addChild(to: item.id) }
            .disabled(!store.canAddChild(to: item.id))
        Button("Novo item irmão") { addSibling(of: item.id) }
        if node.hasChildren {
            Button(node.isCollapsed ? "Expandir" : "Recolher") { settings.toggleCollapsed(item.id) }
        }
        Divider()
        Menu("Mover para") {
            Button("Nível raiz") { performMove(item.id, to: nil) }
                .disabled(!store.canMove(item.id, toParent: nil).isAllowed)
            Divider()
            ForEach(moveTargets(for: item.id)) { target in
                Button(target.title) { performMove(item.id, to: target.id) }
                    .disabled(!store.canMove(item.id, toParent: target.id).isAllowed)
            }
        }
        Button("Mover para cima") { store.shift(item.id, by: -1) }
        Button("Mover para baixo") { store.shift(item.id, by: 1) }
        Divider()
        Button("Excluir", role: .destructive) { askDelete(item) }
    }

    /// Destinos oferecidos no menu "Mover para": raízes e seus filhos diretos.
    private func moveTargets(for id: UUID) -> [TaskItem] {
        store.tasks.flatMap { root in [root] + root.subtasks }
            .filter { $0.id != id }
    }

    // MARK: - Ações

    private func select(_ id: UUID) {
        selectedID = id
        // Durante a edição inline o foco pertence ao campo de título: clicar no
        // próprio card (para posicionar o cursor) não pode devolvê-lo ao canvas.
        if editingID == nil { canvasFocused = true }
    }

    private func deselect() -> KeyPress.Result {
        selectedID = nil
        hoveredID = nil
        draggingID = nil
        return .handled
    }

    private func deselect() { _ = deselect() as KeyPress.Result }

    private func open(_ id: UUID) {
        path.append(.detail(id))
    }

    private func startEditing(_ id: UUID) {
        selectedID = id
        editingID = id
    }

    private func addChild(to parentID: UUID) {
        guard let id = store.insertDraft(under: parentID) else {
            show("Limite de \(settings.maxSubLevels) sub-níveis atingido (ajustável em Configurações).")
            return
        }
        settings.collapsedIDs.remove(parentID)
        startEditing(id)
    }

    private func addSibling(of id: UUID) {
        guard let draft = store.insertDraft(under: store.parentID(of: id), after: id) else { return }
        startEditing(draft)
    }

    private func addChildToSelected() -> KeyPress.Result {
        guard editingID == nil, let selectedID else { return .ignored }
        addChild(to: selectedID)
        return .handled
    }

    private func addSiblingToSelected() -> KeyPress.Result {
        guard editingID == nil, let selectedID else { return .ignored }
        addSibling(of: selectedID)
        return .handled
    }

    private func toggleSelectedDone() -> KeyPress.Result {
        guard editingID == nil, let selectedID else { return .ignored }
        store.toggleDone(id: selectedID)
        return .handled
    }

    private func deleteSelected() -> KeyPress.Result {
        guard editingID == nil, let selectedID, let item = store.find(selectedID) else { return .ignored }
        askDelete(item)
        return .handled
    }

    private func openSelected() -> KeyPress.Result {
        guard editingID == nil, let selectedID else { return .ignored }
        open(selectedID)
        return .handled
    }

    private func performMove(_ id: UUID, to parentID: UUID?) {
        let result = store.move(id, toParent: parentID)
        if let message = result.message { show(message) }
        else if let parentID { settings.collapsedIDs.remove(parentID) }
    }

    /// Rascunhos que sobraram (ex.: navegação no meio da edição).
    private func discardEmptyDrafts() {
        store.discardAllDrafts()
        editingID = nil
    }

    // MARK: - Drop

    private enum DropTarget {
        /// Fundo do mapa: vira raiz.
        case root
        /// Sobre um card, na zona indicada (antes / filho / depois).
        case card(UUID, CardDropZone)
    }

    private func handleDrop(_ providers: [NSItemProvider], target: DropTarget) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, let id = UUID(uuidString: text) else { return }
            Task { @MainActor in
                switch target {
                case .root:
                    performMove(id, to: nil)
                case .card(let targetID, .child):
                    performMove(id, to: targetID)
                case .card(let targetID, let zone):
                    let result = store.move(id, besides: targetID, after: zone == .after)
                    if let message = result.message, result != .sameParent { show(message) }
                }
                draggingID = nil
            }
        }
        return true
    }

    // MARK: - Avisos

    private func show(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Label(toast, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                .padding(10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var hint: some View {
        if selectedID != nil, editingID == nil {
            Text("Tab: sub-item · Enter: irmão · Espaço: concluir · O: abrir · ⌫: excluir")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(.regularMaterial))
                .padding(8)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Conectores

/// Desenha as curvas entre pai e filhos (estilo X-Mind), coloridas por árvore.
private struct ConnectorsView: View {
    let edges: [MindMapLayout.Edge]

    var body: some View {
        Canvas { context, _ in
            for edge in edges {
                var p = Path()
                let midX = (edge.from.x + edge.to.x) / 2
                p.move(to: edge.from)
                p.addCurve(to: edge.to,
                           control1: CGPoint(x: midX, y: edge.from.y),
                           control2: CGPoint(x: midX, y: edge.to.y))
                context.stroke(p, with: .color(MindMapPalette.color(for: edge.rootIndex).opacity(0.7)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }
}
