import Foundation
import UniformTypeIdentifiers

/// Arquivo ou imagem anexado a um item.
/// O conteúdo fica copiado na pasta de anexos do app; `fileName` é o nome físico.
struct Attachment: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// Nome físico dentro da pasta de anexos (uuid + extensão).
    var fileName: String
    /// Nome original exibido ao usuário.
    var displayName: String
    var createdAt: Date = Date()

    var fileExtension: String {
        (fileName as NSString).pathExtension.lowercased()
    }

    var isImage: Bool {
        guard let type = UTType(filenameExtension: fileExtension) else { return false }
        return type.conforms(to: .image)
    }
}

/// Lembrete / data planejada de um item.
/// - `hasTime == true`: o alerta abre na data e hora exatas.
/// - `hasTime == false`: lembrete "do dia" — o alerta abre apenas quando o
///   usuário faz login, desbloqueia a tela, o Mac acorda ou o app é aberto
///   naquele dia ou depois.
struct Reminder: Codable, Hashable {
    var date: Date
    var hasTime: Bool
    /// Quando o usuário dispensou/abriu o alerta. `nil` = ainda pendente.
    var acknowledgedAt: Date? = nil

    var isPending: Bool { acknowledgedAt == nil }

    /// Instante a partir do qual o lembrete está vencido (dispara o alerta).
    var fireDate: Date {
        hasTime ? date : Calendar.current.startOfDay(for: date)
    }

    /// Instante a partir do qual o item conta como **atrasado** em relação ao
    /// planejado: a hora exata, ou o fim do dia quando é lembrete "do dia".
    var deadline: Date {
        if hasTime { return date }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        return cal.date(byAdding: .day, value: 1, to: start) ?? start
    }

    func isDue(at now: Date = Date()) -> Bool {
        isPending && fireDate <= now
    }

    func isLate(at now: Date = Date()) -> Bool {
        deadline <= now
    }

    /// Texto curto para badges e listas: "Hoje 14:30", "Amanhã", "2026-10-03 09:00".
    var label: String {
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(date) { day = "Hoje" }
        else if cal.isDateInTomorrow(date) { day = "Amanhã" }
        else if cal.isDateInYesterday(date) { day = "Ontem" }
        else { day = date.isoDay }
        guard hasTime else { return day }
        return "\(day) \(date.hourMinute)"
    }

    /// Descrição curta do atraso: "3 d", "2 h", "15 min".
    func lateDescription(at now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(deadline))
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(minutes, 1)) min" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h" }
        return "\(hours / 24) d"
    }

    /// Lembrete padrão ao ativar: amanhã, só o dia.
    static func defaultValue(now: Date = Date()) -> Reminder {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        return Reminder(date: cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow,
                        hasTime: false)
    }
}

/// Item da árvore de tarefas. A mesma estrutura vale para qualquer nível:
/// todo item tem título, notas, lembrete, anexos e sub-itens.
struct TaskItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var notes: String = ""
    var isDone: Bool = false
    var createdAt: Date = Date()
    var attachments: [Attachment] = []
    var subtasks: [TaskItem] = []
    var reminder: Reminder? = nil

    /// Lembrete pendente e já vencido (item ainda aberto) — dispara alerta.
    func hasOverdueReminder(at now: Date = Date()) -> Bool {
        !isDone && (reminder?.isDue(at: now) ?? false)
    }

    /// Atrasado em relação ao planejado: aberto e com o prazo já passado,
    /// independentemente de o alerta ter sido dispensado.
    func isLate(at now: Date = Date()) -> Bool {
        !isDone && (reminder?.isLate(at: now) ?? false)
    }

    var doneSubtasks: Int { subtasks.filter { $0.isDone }.count }

    /// Todos os anexos da sub-árvore (inclusive os próprios).
    var allAttachments: [Attachment] {
        attachments + subtasks.flatMap(\.allAttachments)
    }

    /// Total de anexos incluindo os de todos os descendentes.
    var totalAttachments: Int { allAttachments.count }

    /// O item e todos os descendentes, em pré-ordem.
    var flattened: [TaskItem] {
        [self] + subtasks.flatMap(\.flattened)
    }

    /// Quantidade de descendentes (qualquer nível).
    var descendantCount: Int { flattened.count - 1 }

    /// Altura da sub-árvore: 0 para folha, 1 se só tem filhos diretos, etc.
    var subtreeHeight: Int {
        subtasks.isEmpty ? 0 : 1 + (subtasks.map(\.subtreeHeight).max() ?? 0)
    }

    /// Filhos para `List(children:)` (nil quando não há, para não mostrar o disclosure).
    var outlineChildren: [TaskItem]? {
        subtasks.isEmpty ? nil : subtasks
    }
}

// MARK: - Operações de árvore

extension Array where Element == TaskItem {
    /// Caminho de índices até o item (ex.: `[2, 0, 1]`), em qualquer nível.
    func indexPath(of id: UUID) -> [Int]? {
        for (i, item) in enumerated() {
            if item.id == id { return [i] }
            if let sub = item.subtasks.indexPath(of: id) { return [i] + sub }
        }
        return nil
    }

    /// Acesso por caminho de índices (o caminho deve ser válido).
    subscript(path path: [Int]) -> TaskItem {
        get {
            path.count == 1 ? self[path[0]] : self[path[0]].subtasks[path: [Int](path.dropFirst())]
        }
        set {
            if path.count == 1 { self[path[0]] = newValue }
            else { self[path[0]].subtasks[path: [Int](path.dropFirst())] = newValue }
        }
    }

    /// Remove e devolve o item no caminho indicado.
    @discardableResult
    mutating func remove(atPath path: [Int]) -> TaskItem {
        if path.count == 1 { return remove(at: path[0]) }
        return self[path[0]].subtasks.remove(atPath: [Int](path.dropFirst()))
    }

    /// Todos os itens da floresta em pré-ordem.
    var flattened: [TaskItem] { flatMap(\.flattened) }

    func first(withID id: UUID) -> TaskItem? {
        guard let path = indexPath(of: id) else { return nil }
        return self[path: path]
    }

    /// Cópia da floresta só com os itens que passam no filtro. Um item que não
    /// passa mas tem descendente que passa é mantido, para não esconder o caminho.
    func filtered(_ matches: (TaskItem) -> Bool) -> [TaskItem] {
        compactMap { item in
            let subtasks = item.subtasks.filtered(matches)
            guard matches(item) || !subtasks.isEmpty else { return nil }
            var copy = item
            copy.subtasks = subtasks
            return copy
        }
    }

    /// Cópia da floresta sem os itens concluídos (pais concluídos com
    /// descendentes abertos são mantidos).
    func filteringCompleted() -> [TaskItem] {
        filtered { !$0.isDone }
    }
}

// MARK: - Decodificação tolerante

// `init(from:)` manual para que arquivos antigos (ou gerados por fora) sem algum
// campo opcional continuem carregando. Só `title` (item), `fileName`/`displayName`
// (anexo) e `date`/`hasTime` (lembrete) são obrigatórios. Os inits memberwise são
// preservados porque a conformidade fica em extensão.

extension TaskItem {
    private enum CodingKeys: String, CodingKey {
        case id, title, notes, isDone, createdAt, attachments, subtasks, reminder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        subtasks = try c.decodeIfPresent([TaskItem].self, forKey: .subtasks) ?? []
        reminder = try c.decodeIfPresent(Reminder.self, forKey: .reminder)
    }
}

extension Attachment {
    private enum CodingKeys: String, CodingKey { case id, fileName, displayName, createdAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fileName = try c.decode(String.self, forKey: .fileName)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? fileName
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

extension Reminder {
    private enum CodingKeys: String, CodingKey { case date, hasTime, acknowledgedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        hasTime = try c.decodeIfPresent(Bool.self, forKey: .hasTime) ?? false
        acknowledgedAt = try c.decodeIfPresent(Date.self, forKey: .acknowledgedAt)
    }
}

// MARK: - Datas para exibição

extension Date {
    private static func fixedFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        // Formato fixo: en_US_POSIX evita que a preferência 12/24 h do sistema reescreva "HH".
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
    private static let isoShortFormatter = fixedFormatter("yyyy-MM-dd HH:mm")
    private static let isoDayFormatter = fixedFormatter("yyyy-MM-dd")
    private static let hourMinuteFormatter = fixedFormatter("HH:mm")

    /// Formato ISO curto para exibição (YYYY-MM-DD HH:mm).
    var isoShort: String { Self.isoShortFormatter.string(from: self) }

    /// Só a data em ISO (YYYY-MM-DD).
    var isoDay: String { Self.isoDayFormatter.string(from: self) }

    /// Só a hora (HH:mm).
    var hourMinute: String { Self.hourMinuteFormatter.string(from: self) }
}
