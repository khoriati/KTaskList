import XCTest
@testable import KTaskList

final class MindMapLayoutTests: XCTestCase {
    private let metrics = MindMapMetrics.default

    private func forest() -> [TaskItem] {
        var root = TaskItem(title: "R")
        var a = TaskItem(title: "A")
        a.subtasks = [TaskItem(title: "A1"), TaskItem(title: "A2")]
        root.subtasks = [a, TaskItem(title: "B")]
        return [root, TaskItem(title: "S")]
    }

    func testColumnsByDepthAndParentCenteredOnChildren() {
        let forest = forest()
        let layout = MindMapLayout.compute(roots: forest, metrics: metrics)
        XCTAssertEqual(layout.nodes.count, 6)

        let root = layout.node(for: forest[0].id)!
        let a = layout.node(for: forest[0].subtasks[0].id)!
        let a1 = layout.node(for: forest[0].subtasks[0].subtasks[0].id)!
        let a2 = layout.node(for: forest[0].subtasks[0].subtasks[1].id)!

        XCTAssertEqual(root.frame.minX, metrics.padding)
        XCTAssertEqual(a.frame.minX, metrics.padding + metrics.cardWidth + metrics.horizontalGap)
        XCTAssertEqual(a1.frame.minX, a.frame.minX + metrics.cardWidth + metrics.horizontalGap)
        XCTAssertEqual(a.frame.midY, (a1.frame.midY + a2.frame.midY) / 2, accuracy: 0.001)
        XCTAssertEqual(a2.frame.minY, a1.frame.maxY + metrics.verticalGap)

        XCTAssertEqual(layout.edges.count, 4)
        let edgeToA = layout.edges.first { $0.id == a.id }!
        XCTAssertEqual(edgeToA.from.x, root.frame.maxX)
        XCTAssertEqual(edgeToA.to, CGPoint(x: a.frame.minX, y: a.frame.midY))
    }

    func testSecondTreeIsBelowFirstAndSizeCoversEverything() {
        let forest = forest()
        let layout = MindMapLayout.compute(roots: forest, metrics: metrics)
        let firstTreeMaxY = layout.nodes.filter { $0.rootIndex == 0 }.map(\.frame.maxY).max()!
        let second = layout.node(for: forest[1].id)!
        XCTAssertEqual(second.rootIndex, 1)
        XCTAssertEqual(second.frame.minY, firstTreeMaxY + metrics.treeGap, accuracy: 0.001)

        let maxX = layout.nodes.map(\.frame.maxX).max()!
        let maxY = layout.nodes.map(\.frame.maxY).max()!
        XCTAssertGreaterThanOrEqual(layout.size.width, maxX + metrics.trailingControls)
        XCTAssertGreaterThanOrEqual(layout.size.height, maxY)
    }

    func testCollapsedNodeHidesDescendantsAndReportsCount() {
        let forest = forest()
        let a = forest[0].subtasks[0]
        let layout = MindMapLayout.compute(roots: forest, metrics: metrics, collapsed: [a.id])
        XCTAssertEqual(layout.nodes.count, 4)
        let node = layout.node(for: a.id)!
        XCTAssertTrue(node.isCollapsed)
        XCTAssertEqual(node.hiddenDescendants, 2)
        XCTAssertEqual(node.frame.height, metrics.cardHeight)
        XCTAssertFalse(layout.edges.contains { $0.id == a.subtasks[0].id })
    }

    func testEmptyForest() {
        let layout = MindMapLayout.compute(roots: [], metrics: metrics)
        XCTAssertTrue(layout.nodes.isEmpty)
        XCTAssertTrue(layout.edges.isEmpty)
    }
}
