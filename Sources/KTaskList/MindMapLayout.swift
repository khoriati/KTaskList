import Foundation
import SwiftUI

/// Dimensões usadas no mapa (em pontos, antes do zoom).
struct MindMapMetrics {
    var cardWidth: CGFloat = 196
    var cardHeight: CGFloat = 64
    /// Espaço reservado à direita do card para os controles de hover (+, recolher).
    var trailingControls: CGFloat = 26
    var horizontalGap: CGFloat = 52
    var verticalGap: CGFloat = 10
    var treeGap: CGFloat = 26
    var padding: CGFloat = 20

    static let `default` = MindMapMetrics()
}

/// Cores por árvore (índice da raiz), no estilo dos ramos do X-Mind.
enum MindMapPalette {
    static let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown]
    static func color(for rootIndex: Int) -> Color {
        colors[((rootIndex % colors.count) + colors.count) % colors.count]
    }
}

/// Layout horizontal (raízes à esquerda, filhos à direita) de uma floresta de itens.
/// Função pura: recebe a floresta já filtrada e devolve posições e conexões.
struct MindMapLayout {
    struct Node: Identifiable {
        let id: UUID
        let item: TaskItem
        let depth: Int
        let parentID: UUID?
        let rootIndex: Int
        let frame: CGRect
        /// Descendentes visíveis escondidos por estar recolhido (0 se expandido).
        let hiddenDescendants: Int
        var isCollapsed: Bool { hiddenDescendants > 0 }
        var hasChildren: Bool { !item.subtasks.isEmpty }
    }

    struct Edge: Identifiable {
        let id: UUID
        let from: CGPoint
        let to: CGPoint
        let rootIndex: Int
    }

    let nodes: [Node]
    let edges: [Edge]
    let size: CGSize
    let metrics: MindMapMetrics

    func node(for id: UUID) -> Node? { nodes.first { $0.id == id } }

    static func compute(
        roots: [TaskItem],
        metrics: MindMapMetrics = .default,
        collapsed: Set<UUID> = []
    ) -> MindMapLayout {
        var builder = Builder(metrics: metrics, collapsed: collapsed)
        var cursor = metrics.padding
        for (index, root) in roots.enumerated() {
            let height = builder.place(root, depth: 0, rootIndex: index, parentID: nil, y: cursor)
            cursor += height + metrics.treeGap
        }
        let contentHeight = roots.isEmpty ? 0 : cursor - metrics.treeGap
        let columns = CGFloat(builder.maxDepth + 1)
        let width = metrics.padding * 2 + columns * metrics.cardWidth
            + max(0, columns - 1) * metrics.horizontalGap + metrics.trailingControls
        let height = contentHeight + metrics.padding
        return MindMapLayout(
            nodes: builder.nodes,
            edges: builder.edges,
            size: CGSize(width: max(width, 1), height: max(height, 1)),
            metrics: metrics
        )
    }

    private struct Builder {
        let metrics: MindMapMetrics
        let collapsed: Set<UUID>
        var nodes: [Node] = []
        var edges: [Edge] = []
        var maxDepth = 0

        init(metrics: MindMapMetrics, collapsed: Set<UUID>) {
            self.metrics = metrics
            self.collapsed = collapsed
        }

        /// Posiciona o item e sua sub-árvore a partir de `y`; devolve a altura ocupada.
        mutating func place(_ item: TaskItem, depth: Int, rootIndex: Int, parentID: UUID?, y: CGFloat) -> CGFloat {
            maxDepth = max(maxDepth, depth)
            let x = metrics.padding + CGFloat(depth) * (metrics.cardWidth + metrics.horizontalGap)
            let isCollapsed = collapsed.contains(item.id) && !item.subtasks.isEmpty

            guard !item.subtasks.isEmpty, !isCollapsed else {
                let frame = CGRect(x: x, y: y, width: metrics.cardWidth, height: metrics.cardHeight)
                nodes.append(Node(id: item.id, item: item, depth: depth, parentID: parentID,
                                  rootIndex: rootIndex, frame: frame,
                                  hiddenDescendants: isCollapsed ? item.descendantCount : 0))
                return metrics.cardHeight
            }

            var cursor = y
            var childIDs: [UUID] = []
            for child in item.subtasks {
                let h = place(child, depth: depth + 1, rootIndex: rootIndex, parentID: item.id, y: cursor)
                childIDs.append(child.id)
                cursor += h + metrics.verticalGap
            }
            let total = cursor - metrics.verticalGap - y
            let nodeY = y + (total - metrics.cardHeight) / 2
            let frame = CGRect(x: x, y: nodeY, width: metrics.cardWidth, height: metrics.cardHeight)
            nodes.append(Node(id: item.id, item: item, depth: depth, parentID: parentID,
                              rootIndex: rootIndex, frame: frame, hiddenDescendants: 0))

            let from = CGPoint(x: frame.maxX, y: frame.midY)
            for childID in childIDs {
                guard let childFrame = nodes.first(where: { $0.id == childID })?.frame else { continue }
                edges.append(Edge(id: childID, from: from,
                                  to: CGPoint(x: childFrame.minX, y: childFrame.midY),
                                  rootIndex: rootIndex))
            }
            return max(total, metrics.cardHeight)
        }
    }
}
