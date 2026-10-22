import AppKit
import Combine
import SwiftUI
import Foundation
import os
import UniformTypeIdentifiers

/// Resultado da validação de uma movimentação na árvore.
enum MoveCheck: Equatable {
    case ok
    case sameParent
    case intoItself
    case tooDeep(maxSubLevels: Int)
    case notFound

    var isAllowed: Bool { self == .ok }

    var message: String? {
        switch self {
        case .ok: return nil
        case .sameParent: return "O item já está nesse ponto da árvore."
        case .intoItself: return "Não é possível mover um item para dentro dele mesmo."
        case .tooDeep(let max): return "Ultrapassaria o limite de \(max) sub-níveis (ajustável em Configurações)."
        case .notFound: return "Item não encontrado."
        }
    }
}

/// Fonte da verdade da aplicação. Persiste em JSON dentro de
/// `~/Library/Application Support/KTaskList/` e copia anexos para `Attachments/`.
/// Na primeira execução, se existir a pasta `TaskList` (nome antigo do app) e a nova
/// ainda não, ela é renomeada para preservar os dados.
@MainActor
final class TaskStore: ObservableObject {
    @Published var tasks: [TaskItem] = [] {
        didSet { if !isLoading { scheduleSave() } }
    }

    /// Itens criados por `insertDraft` e ainda não confirmados. Só estes podem ser
    /// removidos por título vazio; um item real com título apagado mantém o anterior.
    @Published private(set) var draftIDs: Set<UUID> = []

    let settings: AppSettings
    let baseDirectory: URL
    let dataFileURL: URL
    let backupFileURL: URL
    let attachmentsDirectory: URL

    private let logger = Logger(subsystem: "br.com.khori.ktasklist", category: "store")
    private var saveTask: Task<Void, Never>?
    private var isLoading = false
    private var terminationObserver: NSObjectProtocol?
    /// Verdadeiro quando `tasks.json` existia mas não pôde ser decodificado.
    @Published private(set) var loadFailed = false

    /// Itens abertos em qualquer nível.
    var pendingCount: Int { allTasks.filter { !$0.isDone }.count }
    var doneCount: Int { allTasks.count - pendingCount }
    /// Itens abertos e atrasados em relação ao planejado.
    var lateCount: Int { allTasks.filter { $0.isLate() }.count }

    init(settings: AppSettings, baseDirectory override: URL? = nil) {
        self.settings = settings
        // KTASKLIST_DATA_DIR permite isolar os dados (testes manuais) sem tocar na pasta real.
        if let override {
            baseDirectory = override
        } else if let env = ProcessInfo.processInfo.environment["KTASKLIST_DATA_DIR"], !env.isEmpty {
            baseDirectory = URL(fileURLWithPath: env, isDirectory: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            baseDirectory = support.appendingPathComponent("KTaskList", isDirectory: true)
            Self.migrateLegacyDirectoryIfNeeded(from: support.appendingPathComponent("TaskList", isDirectory: true), to: baseDirectory)
        }
        dataFileURL = baseDirectory.appendingPathComponent("tasks.json")
        backupFileURL = baseDirectory.appendingPathComponent("tasks.backup.json")
        attachmentsDirectory = baseDirectory.appendingPathComponent("Attachments", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("Falha ao criar a pasta de dados: \(error.localizedDescription, privacy: .private)")
        }
        load()
        // Gravação com debounce pendente não pode se perder ao encerrar (Sair, logout, shutdown).
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushPendingSave() }
        }
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    /// Move a pasta de dados do nome antigo (`TaskList`) para o novo, uma única vez.
    /// Só migra se houver um `tasks.json` lá dentro: "TaskList" é um nome genérico e
    /// a pasta pode pertencer a outro app.
    private static func migrateLegacyDirectoryIfNeeded(from legacy: URL, to current: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacy.appendingPathComponent("tasks.json").path),
              !fm.fileExists(atPath: current.path) else { return }
        do {
            try fm.moveItem(at: legacy, to: current)
        } catch {
            Logger(subsystem: "br.com.khori.ktasklist", category: "store")
                .error("Falha ao migrar a pasta TaskList: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: - Persistência

    private func load() {
        guard let data = try? Data(contentsOf: dataFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let loaded = try decoder.decode([TaskItem].self, from: data)
            // Cópia de segurança do último arquivo carregado com sucesso.
            try? data.write(to: backupFileURL, options: .atomic)
            isLoading = true
            tasks = loaded
            isLoading = false
        } catch {
            // Preserva o arquivo ilegível para o usuário recuperar; o app segue vazio e a
            // próxima gravação criará um tasks.json novo (o original fica em .corrupt-*).
            loadFailed = true
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let corrupt = baseDirectory.appendingPathComponent("tasks.corrupt-\(stamp).json")
            try? data.write(to: corrupt, options: .atomic)
            logger.error("Falha ao carregar tarefas (cópia em \(corrupt.lastPathComponent, privacy: .public)): \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Grava imediatamente uma alteração pendente do debounce (encerramento, testes).
    func flushPendingSave() {
        guard let saveTask else { return }
        saveTask.cancel()
        self.saveTask = nil
        save()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(tasks)
            try data.write(to: dataFileURL, options: .atomic)
        } catch {
            logger.error("Falha ao salvar tarefas: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Consulta em qualquer nível

    /// Todos os itens em pré-ordem (raízes seguidas dos seus descendentes).
    var allTasks: [TaskItem] { tasks.flattened }

    func find(_ id: UUID) -> TaskItem? { tasks.first(withID: id) }

    func contains(_ id: UUID) -> Bool { tasks.indexPath(of: id) != nil }

    /// Nível do item: 0 para raiz, 1 para filho de raiz, etc.
    func depth(of id: UUID) -> Int? {
        guard let path = tasks.indexPath(of: id) else { return nil }
        return path.count - 1
    }

    /// Ancestrais do item, da raiz até o pai direto.
    func ancestors(of id: UUID) -> [TaskItem] {
        guard let path = tasks.indexPath(of: id), path.count > 1 else { return [] }
        var result: [TaskItem] = []
        var level = tasks
        for index in path.dropLast() {
            let item = level[index]
            result.append(item)
            level = item.subtasks
        }
        return result
    }

    func parentID(of id: UUID) -> UUID? { ancestors(of: id).last?.id }

    /// Um item pode receber sub-itens enquanto estiver abaixo do limite de níveis.
    func canAddChild(to id: UUID) -> Bool {
        guard let depth = depth(of: id) else { return false }
        return depth < settings.maxSubLevels
    }

    /// Rota de navegação para um item.
    func route(for id: UUID) -> Route? {
        contains(id) ? .detail(id) : nil
    }

    /// Aplica uma alteração em um item pelo id, em qualquer nível.
    func update(_ id: UUID, _ mutate: (inout TaskItem) -> Void) {
        guard let path = tasks.indexPath(of: id) else { return }
        mutate(&tasks[path: path])
    }

    /// Binding para um item pelo id (nil se não existir mais).
    func binding(for id: UUID) -> Binding<TaskItem>? {
        guard contains(id) else { return nil }
        return Binding(
            get: { [weak self] in self?.find(id) ?? TaskItem(title: "") },
            set: { [weak self] newValue in self?.update(id) { $0 = newValue } }
        )
    }

    // MARK: - Criação

    /// Cria um item raiz (no topo da lista) com o título informado.
    @discardableResult
    func addTask(title: String) -> TaskItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let task = TaskItem(title: trimmed)
        tasks.insert(task, at: 0)
        return task
    }

    /// Cria um sub-item ao final dos filhos de `parentID`, respeitando o limite de níveis.
    @discardableResult
    func addSubtask(to parentID: UUID, title: String) -> TaskItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canAddChild(to: parentID) else { return nil }
        let sub = TaskItem(title: trimmed)
        update(parentID) { $0.subtasks.append(sub) }
        return sub
    }

    /// Cria um item vazio (para edição inline no mapa). Devolve o id ou nil se
    /// o limite de níveis impedir. Use `commitTitle` para confirmar ou descartar.
    func insertDraft(under parentID: UUID?, after siblingID: UUID? = nil) -> UUID? {
        let draft = TaskItem(title: "")
        if let parentID {
            guard canAddChild(to: parentID) else { return nil }
            update(parentID) { parent in
                if let siblingID, let i = parent.subtasks.firstIndex(where: { $0.id == siblingID }) {
                    parent.subtasks.insert(draft, at: i + 1)
                } else {
                    parent.subtasks.append(draft)
                }
            }
        } else if let siblingID, let i = tasks.firstIndex(where: { $0.id == siblingID }) {
            tasks.insert(draft, at: i + 1)
        } else {
            tasks.append(draft)
        }
        draftIDs.insert(draft.id)
        return draft.id
    }

    /// Confirma o título editado inline. Título vazio em rascunho remove o item;
    /// em item existente mantém o título anterior.
    func commitTitle(_ id: UUID, _ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard contains(id) else { return }
        if trimmed.isEmpty {
            if draftIDs.contains(id) { deleteTask(id: id) }
            return
        }
        draftIDs.remove(id)
        update(id) { $0.title = trimmed }
    }

    /// Remove um rascunho ainda não confirmado (ex.: edição cancelada). Itens reais
    /// nunca são removidos por aqui, mesmo com título vazio.
    func discardDraft(_ id: UUID) {
        guard draftIDs.contains(id) else { return }
        deleteTask(id: id)
    }

    /// Remove todos os rascunhos pendentes (ex.: navegação no meio da edição).
    func discardAllDrafts() {
        draftIDs.forEach(deleteTask)
    }

    // MARK: - Alterações

    func deleteTask(id: UUID) {
        guard let path = tasks.indexPath(of: id) else { return }
        let removed = tasks.remove(atPath: path)
        removed.allAttachments.forEach(deleteFile)
        let ids = removed.flattened.map(\.id)
        settings.collapsedIDs.subtract(ids)
        draftIDs.subtract(ids)
    }

    func toggleDone(id: UUID) {
        update(id) { $0.isDone.toggle() }
    }

    func markDone(_ id: UUID) {
        update(id) { $0.isDone = true }
    }

    /// Remove os itens concluídos de todos os níveis (com anexos).
    func clearCompleted() {
        allTasks.filter(\.isDone).map(\.id).forEach { id in
            // O item pode já ter saído junto com um ancestral concluído.
            if contains(id) { deleteTask(id: id) }
        }
    }

    // MARK: - Movimentação na árvore

    /// Verifica se `id` pode virar filho de `newParentID` (nil = raiz).
    /// Com `allowSameParent` a checagem serve para reordenar entre irmãos.
    func canMove(_ id: UUID, toParent newParentID: UUID?, allowSameParent: Bool = false) -> MoveCheck {
        guard let item = find(id) else { return .notFound }
        if !allowSameParent, parentID(of: id) == newParentID { return .sameParent }
        guard let newParentID else { return .ok }
        guard let parentDepth = depth(of: newParentID) else { return .notFound }
        if item.flattened.contains(where: { $0.id == newParentID }) { return .intoItself }
        if parentDepth + 1 + item.subtreeHeight > settings.maxSubLevels {
            return .tooDeep(maxSubLevels: settings.maxSubLevels)
        }
        return .ok
    }

    /// Move o item (com toda a sub-árvore) para o final dos filhos de `newParentID`
    /// (nil = raiz). Devolve o resultado da validação.
    @discardableResult
    func move(_ id: UUID, toParent newParentID: UUID?) -> MoveCheck {
        let check = canMove(id, toParent: newParentID)
        guard check.isAllowed, let path = tasks.indexPath(of: id) else { return check }
        var snapshot = tasks
        let item = snapshot.remove(atPath: path)
        if let newParentID, let parentPath = snapshot.indexPath(of: newParentID) {
            snapshot[path: parentPath].subtasks.append(item)
        } else {
            snapshot.append(item)
        }
        tasks = snapshot
        return .ok
    }

    /// Verifica se `id` pode ser colocado como irmão de `siblingID`.
    func canMove(_ id: UUID, besides siblingID: UUID) -> MoveCheck {
        guard id != siblingID else { return .sameParent }
        guard contains(siblingID) else { return .notFound }
        return canMove(id, toParent: parentID(of: siblingID), allowSameParent: true)
    }

    /// Move o item (com a sub-árvore) para antes ou depois de `siblingID`,
    /// no mesmo nível dele — inclusive entre irmãos, para reordenar.
    @discardableResult
    func move(_ id: UUID, besides siblingID: UUID, after: Bool) -> MoveCheck {
        let check = canMove(id, besides: siblingID)
        guard check.isAllowed, let path = tasks.indexPath(of: id) else { return check }
        var snapshot = tasks
        let item = snapshot.remove(atPath: path)
        guard let siblingPath = snapshot.indexPath(of: siblingID) else { return .notFound }
        let index = siblingPath[siblingPath.count - 1] + (after ? 1 : 0)
        if siblingPath.count == 1 {
            snapshot.insert(item, at: index)
        } else {
            snapshot[path: Array(siblingPath.dropLast())].subtasks.insert(item, at: index)
        }
        tasks = snapshot
        return .ok
    }

    /// Troca a posição do item com o irmão anterior (-1) ou seguinte (+1).
    func shift(_ id: UUID, by offset: Int) {
        guard let path = tasks.indexPath(of: id) else { return }
        let index = path[path.count - 1]
        let target = index + offset
        if path.count == 1 {
            guard tasks.indices.contains(target) else { return }
            tasks.swapAt(index, target)
        } else {
            let parentPath = Array(path.dropLast())
            guard tasks[path: parentPath].subtasks.indices.contains(target) else { return }
            tasks[path: parentPath].subtasks.swapAt(index, target)
        }
    }

    // MARK: - Lembretes

    /// Marca o lembrete como visto (não dispara novamente).
    func acknowledgeReminder(_ id: UUID) {
        update(id) { $0.reminder?.acknowledgedAt = Date() }
    }

    /// Reagenda o lembrete para um novo instante (sempre com horário).
    func snoozeReminder(_ id: UUID, until date: Date) {
        update(id) { $0.reminder = Reminder(date: date, hasTime: true) }
    }

    // MARK: - Anexos

    /// URL do arquivo do anexo. Só o último componente de `fileName` é usado, para
    /// que um JSON editado por fora nunca aponte para fora da pasta de anexos.
    func fileURL(for attachment: Attachment) -> URL {
        attachmentsDirectory.appendingPathComponent((attachment.fileName as NSString).lastPathComponent)
    }

    /// Copia um arquivo externo para a pasta de anexos.
    func importFile(from sourceURL: URL) throws -> Attachment {
        let ext = sourceURL.pathExtension
        let id = UUID()
        let fileName = ext.isEmpty ? id.uuidString : "\(id.uuidString).\(ext)"
        let destination = attachmentsDirectory.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return Attachment(id: id, fileName: fileName, displayName: sourceURL.lastPathComponent)
    }

    /// Grava dados brutos (ex.: imagem colada) como anexo.
    func importData(_ data: Data, fileExtension: String, displayName: String? = nil) throws -> Attachment {
        let id = UUID()
        let fileName = "\(id.uuidString).\(fileExtension)"
        let destination = attachmentsDirectory.appendingPathComponent(fileName)
        try data.write(to: destination, options: .atomic)
        let name = displayName ?? "Imagem \(Date().isoShort).\(fileExtension)"
        return Attachment(id: id, fileName: fileName, displayName: name)
    }

    func deleteFile(_ attachment: Attachment) {
        let url = fileURL(for: attachment)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logger.error("Falha ao remover anexo: \(error.localizedDescription, privacy: .private)")
        }
    }

    func open(_ attachment: Attachment) {
        NSWorkspace.shared.open(fileURL(for: attachment))
    }

    func revealInFinder(_ attachment: Attachment) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL(for: attachment)])
    }

    func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([dataFileURL])
    }
}
