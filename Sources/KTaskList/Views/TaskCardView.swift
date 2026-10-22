import SwiftUI
import UniformTypeIdentifiers

/// Onde um item arrastado será solto em relação a este card.
enum CardDropZone: Equatable {
    /// Borda superior: vira irmão antes deste card.
    case before
    /// Centro: vira filho deste card.
    case child
    /// Borda inferior: vira irmão depois deste card.
    case after

    static func zone(forY y: CGFloat, height: CGFloat) -> CardDropZone {
        let edge = height * 0.28
        if y < edge { return .before }
        if y > height - edge { return .after }
        return .child
    }
}

/// Card de um item no mapa. À direita fica uma faixa com os controles de hover
/// (criar sub-item, recolher/expandir), como no X-Mind.
struct TaskCardView: View {
    let node: MindMapLayout.Node
    let color: Color
    let isSelected: Bool
    let isHovered: Bool
    let isEditing: Bool
    let canAddChild: Bool
    let maxSubLevels: Int
    /// Validação do item sendo arrastado contra este card e zona (nil = nada arrastando).
    let dropCheck: (CardDropZone) -> MoveCheck?
    let onHover: (Bool) -> Void
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onToggleDone: () -> Void
    let onAddChild: () -> Void
    let onToggleCollapse: () -> Void
    let onCommitTitle: (String) -> Void
    let onCancelEdit: () -> Void
    let onDragStart: () -> NSItemProvider
    let onDrop: ([NSItemProvider], CardDropZone) -> Bool

    @State private var dropZone: CardDropZone?

    private var item: TaskItem { node.item }
    private var showsControls: Bool { isHovered || isSelected }

    var body: some View {
        HStack(spacing: 0) {
            body_
            trailingControls
        }
        .contentShape(Rectangle())
        .onHover(perform: onHover)
    }

    // MARK: - Corpo

    private var body_: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggleDone) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(item.isDone ? color : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(item.isDone ? "Reabrir" : "Concluir")
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                if isEditing {
                    InlineTitleEditor(initial: item.title, onCommit: onCommitTitle, onCancel: onCancelEdit)
                } else {
                    Text(item.title.isEmpty ? "Sem título" : item.title)
                        .font(node.depth == 0 ? .callout.weight(.semibold) : .callout)
                        .strikethrough(item.isDone)
                        .foregroundStyle(item.isDone ? .secondary : .primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TaskBadges(task: item)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 10).fill(backgroundColor))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(item.isDone ? 0.35 : 1))
                .frame(width: 3)
                .padding(.vertical, 9)
                .padding(.leading, 3)
        }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(borderColor, lineWidth: borderWidth))
        .shadow(color: .black.opacity(isHovered || isSelected ? 0.14 : 0.06), radius: isHovered ? 5 : 2, y: 1)
        .opacity(item.isDone && !isSelected ? 0.55 : 1)
        .onTapGesture(count: 2, perform: onOpen)
        .onTapGesture(count: 1, perform: onSelect)
        .overlay(alignment: .top) { insertionMarker(for: .before) }
        .overlay(alignment: .bottom) { insertionMarker(for: .after) }
        .modifier(DragIfAllowed(enabled: !isEditing, onDragStart: onDragStart))
        .onDrop(of: [.text], delegate: CardDropDelegate(zone: $dropZone, perform: onDrop))
        .help(item.title.count > 40 ? item.title : "")
        .animation(.easeInOut(duration: 0.12), value: dropZone)
    }

    private var dropState: MoveCheck? { dropZone.flatMap(dropCheck) }

    /// Linha de inserção acima/abaixo do card ao soltar como irmão.
    @ViewBuilder
    private func insertionMarker(for zone: CardDropZone) -> some View {
        if dropZone == zone, let dropState {
            Capsule()
                .fill(dropState.isAllowed ? color : Color.red)
                .frame(height: 3)
                .padding(.horizontal, 6)
                .offset(y: zone == .before ? -6 : 6)
        }
    }

    private var backgroundColor: Color {
        if let dropState, dropZone == .child {
            return dropState.isAllowed ? color.opacity(0.18) : Color.red.opacity(0.12)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if let dropState, dropZone == .child { return dropState.isAllowed ? color : .red }
        if isSelected { return Color.accentColor }
        if item.isLate() { return Color.red.opacity(0.7) }
        return Color.secondary.opacity(isHovered ? 0.45 : 0.25)
    }

    private var borderWidth: CGFloat {
        (dropState != nil && dropZone == .child) || isSelected ? 2 : 1
    }

    // MARK: - Controles à direita

    private var trailingControls: some View {
        VStack(spacing: 4) {
            if node.hasChildren {
                Button(action: onToggleCollapse) {
                    ZStack {
                        Circle().fill(Color(nsColor: .controlBackgroundColor))
                        Circle().strokeBorder(color.opacity(0.8), lineWidth: 1.5)
                        if node.isCollapsed {
                            Text("\(node.hiddenDescendants)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(color)
                        } else {
                            Image(systemName: "minus")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(color)
                        }
                    }
                    .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(node.isCollapsed ? "Expandir \(node.hiddenDescendants) item(ns)" : "Recolher")
                .opacity(node.isCollapsed || showsControls ? 1 : 0)
            }
            if showsControls && !isEditing {
                Button(action: onAddChild) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(canAddChild ? color : Color.secondary.opacity(0.5))
                        .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                }
                .buttonStyle(.plain)
                .disabled(!canAddChild)
                .help(canAddChild ? "Novo sub-item" : "Limite de \(maxSubLevels) sub-níveis atingido")
            }
        }
        .frame(width: 26)
        .frame(maxHeight: .infinity)
    }
}

/// Acompanha a posição do cursor durante o arrasto para escolher a zona
/// (antes / filho / depois) e executa a soltura.
private struct CardDropDelegate: DropDelegate {
    @Binding var zone: CardDropZone?
    let perform: ([NSItemProvider], CardDropZone) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        zone = CardDropZone.zone(forY: info.location.y, height: MindMapMetrics.default.cardHeight)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        zone = CardDropZone.zone(forY: info.location.y, height: MindMapMetrics.default.cardHeight)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        zone = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let current = zone ?? CardDropZone.zone(forY: info.location.y, height: MindMapMetrics.default.cardHeight)
        zone = nil
        return perform(info.itemProviders(for: [.text]), current)
    }
}

/// Aplica `onDrag` só quando permitido (não durante a edição do título).
private struct DragIfAllowed: ViewModifier {
    let enabled: Bool
    let onDragStart: () -> NSItemProvider

    func body(content: Content) -> some View {
        if enabled {
            content.onDrag(onDragStart)
        } else {
            content
        }
    }
}

/// Campo de título inline: Enter confirma, Esc cancela, perder o foco confirma.
///
/// O foco é pedido em várias tentativas curtas: o campo pode entrar na hierarquia
/// um ciclo depois de aparecer (o card nasce junto com o rascunho e o layout do
/// mapa é recalculado), e em Macs mais rápidos uma única chamada assíncrona
/// podia chegar antes do `NSTextField` existir, deixando a caixa sem teclado.
/// Enquanto o campo nunca teve foco, a perda de foco é ignorada, para que uma
/// tentativa falha não confirme (e descarte) o rascunho vazio.
private struct InlineTitleEditor: View {
    let initial: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @State private var finished = false
    @State private var hadFocus = false
    @State private var focusAttempts: Task<Void, Never>?
    @FocusState private var focused: Bool

    private static let focusRetryDelays: [Duration] = [.zero, .milliseconds(40), .milliseconds(120), .milliseconds(300), .milliseconds(600)]

    var body: some View {
        TextField("Título", text: $text)
            .textFieldStyle(.plain)
            .font(.callout)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .textBackgroundColor)))
            .focused($focused)
            .onSubmit { finish { onCommit(text) } }
            .onExitCommand { finish(onCancel) }
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    hadFocus = true
                    focusAttempts?.cancel()
                } else if hadFocus {
                    finish { onCommit(text) }
                }
            }
            .onAppear {
                text = initial
                requestFocus()
            }
            .onDisappear { focusAttempts?.cancel() }
    }

    /// Ativa o app (popover de barra de menu não ativa sozinho) e insiste no foco
    /// até o campo aceitá-lo ou as tentativas acabarem.
    private func requestFocus() {
        focusAttempts?.cancel()
        focusAttempts = Task { @MainActor in
            if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
            for delay in Self.focusRetryDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, !finished, !focused else { return }
                focused = true
            }
        }
    }

    private func finish(_ action: () -> Void) {
        guard !finished else { return }
        finished = true
        focusAttempts?.cancel()
        action()
    }
}
