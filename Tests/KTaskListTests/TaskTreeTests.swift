import XCTest
@testable import KTaskList

@MainActor
final class TaskTreeTests: XCTestCase {
    private var tempDir: URL!
    private var settings: AppSettings!
    private var store: TaskStore!
    private var suiteName = ""

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktasklist-tests-\(UUID().uuidString)", isDirectory: true)
        suiteName = "ktasklist-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        settings = AppSettings(defaults: defaults)
        store = TaskStore(settings: settings, baseDirectory: tempDir)
    }

    override func tearDown() async throws {
        // Grava o que estiver pendente antes de apagar a pasta e não deixa plist em ~/Library/Preferences.
        store.flushPendingSave()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Monta raiz > filho > neto e devolve os ids.
    private func makeChain() -> (root: UUID, child: UUID, grandchild: UUID) {
        let root = store.addTask(title: "Raiz")!
        let child = store.addSubtask(to: root.id, title: "Filho")!
        let grandchild = store.addSubtask(to: child.id, title: "Neto")!
        return (root.id, child.id, grandchild.id)
    }

    func testDepthAndAncestors() {
        let ids = makeChain()
        XCTAssertEqual(store.depth(of: ids.root), 0)
        XCTAssertEqual(store.depth(of: ids.child), 1)
        XCTAssertEqual(store.depth(of: ids.grandchild), 2)
        XCTAssertEqual(store.ancestors(of: ids.grandchild).map(\.title), ["Raiz", "Filho"])
        XCTAssertEqual(store.parentID(of: ids.child), ids.root)
        XCTAssertNil(store.parentID(of: ids.root))
    }

    func testMaxSubLevelsBlocksDeeperCreation() {
        settings.maxSubLevels = 2
        let ids = makeChain()
        XCTAssertTrue(store.canAddChild(to: ids.child))
        XCTAssertFalse(store.canAddChild(to: ids.grandchild))
        XCTAssertNil(store.addSubtask(to: ids.grandchild, title: "Bisneto"))
        XCTAssertNil(store.insertDraft(under: ids.grandchild))

        settings.maxSubLevels = 3
        XCTAssertNotNil(store.addSubtask(to: ids.grandchild, title: "Bisneto"))
    }

    func testUpdateAtAnyLevel() {
        let ids = makeChain()
        store.update(ids.grandchild) { $0.title = "Neto editado"; $0.isDone = true }
        XCTAssertEqual(store.find(ids.grandchild)?.title, "Neto editado")
        XCTAssertEqual(store.find(ids.grandchild)?.isDone, true)
        XCTAssertEqual(store.doneCount, 1)
        XCTAssertEqual(store.pendingCount, 2)
    }

    func testMoveToOtherTreeAndToRoot() {
        let ids = makeChain()
        let other = store.addTask(title: "Outra raiz")!

        XCTAssertEqual(store.move(ids.child, toParent: other.id), .ok)
        XCTAssertEqual(store.parentID(of: ids.child), other.id)
        XCTAssertEqual(store.depth(of: ids.grandchild), 2)
        XCTAssertTrue(store.find(ids.root)!.subtasks.isEmpty)

        XCTAssertEqual(store.move(ids.grandchild, toParent: nil), .ok)
        XCTAssertEqual(store.depth(of: ids.grandchild), 0)
        XCTAssertEqual(store.tasks.last?.id, ids.grandchild)
    }

    func testMoveValidation() {
        settings.maxSubLevels = 3
        let ids = makeChain()
        let other = store.addTask(title: "Outra raiz")!
        let otherChild = store.addSubtask(to: other.id, title: "Filho da outra")!

        XCTAssertEqual(store.canMove(ids.root, toParent: ids.grandchild), .intoItself)
        XCTAssertEqual(store.canMove(ids.child, toParent: ids.root), .sameParent)
        XCTAssertEqual(store.canMove(ids.root, toParent: nil), .sameParent)
        // raiz (altura 2) sob um item de nível 1 → níveis 2, 3 e 4: excede 3.
        XCTAssertEqual(store.canMove(ids.root, toParent: otherChild.id), .tooDeep(maxSubLevels: 3))
        // sob a outra raiz cabe: níveis 1, 2 e 3.
        XCTAssertEqual(store.canMove(ids.root, toParent: other.id), .ok)
        XCTAssertEqual(store.canMove(UUID(), toParent: nil), .notFound)
    }

    func testShiftAmongSiblings() {
        let root = store.addTask(title: "Raiz")!
        let a = store.addSubtask(to: root.id, title: "A")!
        let b = store.addSubtask(to: root.id, title: "B")!
        store.shift(b.id, by: -1)
        XCTAssertEqual(store.find(root.id)?.subtasks.map(\.id), [b.id, a.id])
        store.shift(b.id, by: -1) // já é o primeiro: sem efeito
        XCTAssertEqual(store.find(root.id)?.subtasks.first?.id, b.id)
    }

    func testDraftCommitAndDiscard() {
        let root = store.addTask(title: "Raiz")!
        let draft = store.insertDraft(under: root.id)!
        store.commitTitle(draft, "   ")
        XCTAssertNil(store.find(draft), "rascunho vazio deve ser removido")

        let draft2 = store.insertDraft(under: nil, after: root.id)!
        XCTAssertEqual(store.tasks.map(\.id), [root.id, draft2])
        store.commitTitle(draft2, "  Novo  ")
        XCTAssertEqual(store.find(draft2)?.title, "Novo")

        store.commitTitle(draft2, "")
        XCTAssertEqual(store.find(draft2)?.title, "Novo", "item existente mantém o título")
    }

    func testDeleteRemovesSubtreeAttachmentsAndCollapsedState() throws {
        let ids = makeChain()
        let attachment = try store.importData(Data("x".utf8), fileExtension: "txt")
        store.update(ids.grandchild) { $0.attachments = [attachment] }
        settings.collapsedIDs = [ids.child]

        store.deleteTask(id: ids.root)
        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: attachment).path))
        XCTAssertTrue(settings.collapsedIDs.isEmpty)
    }

    func testFilteringCompletedKeepsDoneParentsWithOpenChildren() {
        let ids = makeChain()
        let done = store.addTask(title: "Concluída")!
        store.markDone(done.id)
        store.markDone(ids.root)

        let visible = store.tasks.filteringCompleted()
        XCTAssertEqual(visible.map(\.id), [ids.root], "raiz concluída com descendentes abertos permanece")
        XCTAssertEqual(visible.first?.subtasks.first?.id, ids.child)

        store.markDone(ids.child)
        store.markDone(ids.grandchild)
        XCTAssertTrue(store.tasks.filteringCompleted().isEmpty)
    }

    func testLateDetection() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 15))!
        var item = TaskItem(title: "x")

        item.reminder = Reminder(date: now.addingTimeInterval(-3600), hasTime: true)
        XCTAssertTrue(item.isLate(at: now))
        XCTAssertEqual(item.reminder?.lateDescription(at: now), "1 h")

        // Lembrete "do dia" de hoje ainda não está atrasado; o de ontem está.
        item.reminder = Reminder(date: cal.startOfDay(for: now), hasTime: false)
        XCTAssertFalse(item.isLate(at: now))
        item.reminder = Reminder(date: cal.date(byAdding: .day, value: -1, to: now)!, hasTime: false)
        XCTAssertTrue(item.isLate(at: now))

        item.isDone = true
        XCTAssertFalse(item.isLate(at: now))
    }

    func testPersistenceRoundTripAndBackup() throws {
        let ids = makeChain()
        store.save()
        let reloaded = TaskStore(settings: settings, baseDirectory: tempDir)
        XCTAssertEqual(reloaded.find(ids.grandchild)?.title, "Neto")
        XCTAssertTrue(FileManager.default.fileExists(atPath: reloaded.backupFileURL.path))
    }
}

@MainActor
final class TaskReorderTests: XCTestCase {
    private var tempDir: URL!
    private var settings: AppSettings!
    private var store: TaskStore!
    private var suiteName = ""

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktasklist-tests-\(UUID().uuidString)", isDirectory: true)
        suiteName = "ktasklist-tests-\(UUID().uuidString)"
        settings = AppSettings(defaults: UserDefaults(suiteName: suiteName)!)
        store = TaskStore(settings: settings, baseDirectory: tempDir)
    }

    override func tearDown() async throws {
        store.flushPendingSave()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testReorderRootsByDroppingBesides() {
        let c = store.addTask(title: "C")!
        let b = store.addTask(title: "B")!
        let a = store.addTask(title: "A")!
        XCTAssertEqual(store.tasks.map(\.title), ["A", "B", "C"])

        XCTAssertEqual(store.move(a.id, besides: c.id, after: true), .ok)
        XCTAssertEqual(store.tasks.map(\.title), ["B", "C", "A"])

        XCTAssertEqual(store.move(a.id, besides: b.id, after: false), .ok)
        XCTAssertEqual(store.tasks.map(\.title), ["A", "B", "C"])
        XCTAssertEqual(store.depth(of: a.id), 0)
    }

    func testReorderChildrenAndMoveBetweenParents() {
        let root = store.addTask(title: "R")!
        let x = store.addSubtask(to: root.id, title: "X")!
        let y = store.addSubtask(to: root.id, title: "Y")!
        let z = store.addSubtask(to: root.id, title: "Z")!
        let other = store.addTask(title: "O")!
        let o1 = store.addSubtask(to: other.id, title: "O1")!

        XCTAssertEqual(store.move(z.id, besides: x.id, after: false), .ok)
        XCTAssertEqual(store.find(root.id)?.subtasks.map(\.title), ["Z", "X", "Y"])

        // Para outra árvore, antes de O1: vira irmão dele, no nível 1.
        XCTAssertEqual(store.move(y.id, besides: o1.id, after: false), .ok)
        XCTAssertEqual(store.find(other.id)?.subtasks.map(\.title), ["Y", "O1"])
        XCTAssertEqual(store.find(root.id)?.subtasks.map(\.title), ["Z", "X"])
        XCTAssertEqual(store.depth(of: y.id), 1)
    }

    func testReorderValidation() {
        settings.maxSubLevels = 2
        let root = store.addTask(title: "R")!
        let child = store.addSubtask(to: root.id, title: "C")!
        let grandchild = store.addSubtask(to: child.id, title: "G")!
        let other = store.addTask(title: "O")!

        XCTAssertEqual(store.canMove(root.id, besides: grandchild.id), .intoItself)
        XCTAssertEqual(store.canMove(root.id, besides: child.id), .intoItself)
        XCTAssertEqual(store.canMove(child.id, besides: child.id), .sameParent)
        // "O" (folha) cabe como irmão de G (nível 2).
        XCTAssertEqual(store.canMove(other.id, besides: grandchild.id), .ok)
        XCTAssertEqual(store.move(other.id, besides: grandchild.id, after: true), .ok)
        XCTAssertEqual(store.find(child.id)?.subtasks.map(\.title), ["G", "O"])
        // root não pode ir para o lado de um descendente seu.
        XCTAssertEqual(store.canMove(root.id, besides: other.id), .intoItself)
        // Uma árvore de altura 2 ao lado de "O" (nível 2) excede o limite de 2.
        let tall = store.addTask(title: "Alta")!
        let mid = store.addSubtask(to: tall.id, title: "Meio")!
        _ = store.addSubtask(to: mid.id, title: "Fundo")!
        XCTAssertEqual(store.canMove(tall.id, besides: other.id), .tooDeep(maxSubLevels: 2))
    }

    func testDropZoneByPosition() {
        XCTAssertEqual(CardDropZone.zone(forY: 5, height: 64), .before)
        XCTAssertEqual(CardDropZone.zone(forY: 32, height: 64), .child)
        XCTAssertEqual(CardDropZone.zone(forY: 60, height: 64), .after)
    }
}

@MainActor
final class QuickFilterTests: XCTestCase {
    func testFilterKeepsAncestorsOfMatches() {
        var root = TaskItem(title: "R", isDone: true)
        var child = TaskItem(title: "C", isDone: true)
        let late = TaskItem(title: "L", reminder: Reminder(date: Date(timeIntervalSinceNow: -86400 * 2), hasTime: true))
        child.subtasks = [late, TaskItem(title: "ok")]
        root.subtasks = [child]
        let other = TaskItem(title: "O")

        let settings = AppSettings(defaults: UserDefaults(suiteName: "filter-\(UUID().uuidString)")!)
        settings.onlyLate = true
        let visible = [root, other].filtered { settings.matchesFilter($0) }
        XCTAssertEqual(visible.map(\.title), ["R"])
        XCTAssertEqual(visible[0].subtasks[0].subtasks.map(\.title), ["L"])

        settings.onlyLate = false
        settings.showPending = false
        let doneOnly = [root, other].filtered { settings.matchesFilter($0) }
        XCTAssertEqual(doneOnly.map(\.title), ["R"])
        XCTAssertTrue(doneOnly[0].subtasks[0].subtasks.isEmpty)

        settings.showCompleted = false
        XCTAssertTrue([root, other].filtered { settings.matchesFilter($0) }.isEmpty)
    }
}
