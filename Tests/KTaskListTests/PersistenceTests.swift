import XCTest
@testable import KTaskList

/// Persistência e tolerância do formato `tasks.json`.
@MainActor
final class PersistenceTests: XCTestCase {
    private var tempDir: URL!
    private var suiteName = ""
    private var settings: AppSettings!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktasklist-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        suiteName = "ktasklist-tests-\(UUID().uuidString)"
        settings = AppSettings(defaults: UserDefaults(suiteName: suiteName)!)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ json: String) throws {
        try json.data(using: .utf8)!.write(to: tempDir.appendingPathComponent("tasks.json"))
    }

    func testMissingOptionalKeysLoadWithDefaults() throws {
        try write(#"[{"title":"Só título","subtasks":[{"title":"Filho","reminder":{"date":"2026-10-21T12:00:00Z"}}]}]"#)
        let store = TaskStore(settings: settings, baseDirectory: tempDir)
        XCTAssertFalse(store.loadFailed)
        XCTAssertEqual(store.tasks.count, 1)
        let root = store.tasks[0]
        XCTAssertEqual(root.title, "Só título")
        XCTAssertEqual(root.notes, "")
        XCTAssertFalse(root.isDone)
        XCTAssertEqual(root.attachments, [])
        XCTAssertEqual(root.subtasks.first?.title, "Filho")
        XCTAssertEqual(root.subtasks.first?.reminder?.hasTime, false)
        XCTAssertNil(root.subtasks.first?.reminder?.acknowledgedAt)
    }

    func testMissingTitleIsRejectedAndFilePreserved() throws {
        try write(#"[{"notes":"sem título"}]"#)
        let store = TaskStore(settings: settings, baseDirectory: tempDir)
        XCTAssertTrue(store.loadFailed)
        XCTAssertTrue(store.tasks.isEmpty)
        let copies = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
            .filter { $0.hasPrefix("tasks.corrupt-") }
        XCTAssertEqual(copies.count, 1, "o arquivo ilegível deve ser preservado em tasks.corrupt-*.json")
    }

    func testLoadDoesNotRewriteFile() throws {
        let json = #"[{"title":"x"}]"#
        try write(json)
        let store = TaskStore(settings: settings, baseDirectory: tempDir)
        XCTAssertEqual(store.tasks.count, 1)
        // Sem alterações do usuário, nenhuma gravação é agendada.
        store.flushPendingSave()
        let after = try String(contentsOf: tempDir.appendingPathComponent("tasks.json"), encoding: .utf8)
        XCTAssertEqual(after, json)
    }

    func testFlushPendingSaveWritesImmediately() throws {
        let store = TaskStore(settings: settings, baseDirectory: tempDir)
        _ = store.addTask(title: "Urgente")
        store.flushPendingSave()
        let data = try Data(contentsOf: tempDir.appendingPathComponent("tasks.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode([TaskItem].self, from: data).first?.title, "Urgente")
    }

    func testAttachmentFileNameCannotEscapeAttachmentsFolder() {
        let store = TaskStore(settings: settings, baseDirectory: tempDir)
        let url = store.fileURL(for: Attachment(fileName: "../../etc/passwd", displayName: "x"))
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, store.attachmentsDirectory.standardizedFileURL)
        XCTAssertEqual(url.lastPathComponent, "passwd")
    }

    func testEmptyTitleOnlyDeletesDrafts() {
        let store = TaskStore(settings: settings, baseDirectory: tempDir)
        let real = store.addTask(title: "Real")!
        _ = store.addSubtask(to: real.id, title: "Filho")
        store.commitTitle(real.id, "   ")
        XCTAssertEqual(store.find(real.id)?.title, "Real", "item real mantém o título anterior")
        store.discardDraft(real.id)
        XCTAssertNotNil(store.find(real.id), "discardDraft nunca remove item real")

        let draft = store.insertDraft(under: real.id)!
        XCTAssertTrue(store.draftIDs.contains(draft))
        store.commitTitle(draft, "")
        XCTAssertNil(store.find(draft))
        XCTAssertFalse(store.draftIDs.contains(draft))

        let draft2 = store.insertDraft(under: nil)!
        store.commitTitle(draft2, "Confirmado")
        XCTAssertFalse(store.draftIDs.contains(draft2))
        store.discardDraft(draft2)
        XCTAssertNotNil(store.find(draft2), "após confirmar, deixa de ser rascunho")
    }
}
