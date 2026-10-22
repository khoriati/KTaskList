import Combine
import Foundation

/// Preferências do usuário, persistidas em UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    enum ViewMode: String, CaseIterable, Identifiable {
        case map, list
        var id: String { rawValue }
        var title: String { self == .map ? "Mapa" : "Lista" }
        var systemImage: String { self == .map ? "point.3.connected.trianglepath.dotted" : "list.bullet.indent" }
    }

    static let defaultMaxSubLevels = 3
    static let subLevelsRange = 1...6
    static let zoomRange = 0.5...1.6
    static let zoomStep = 0.1

    private enum Key {
        static let maxSubLevels = "maxSubLevels"
        static let showCompleted = "showCompleted"
        static let showPending = "showPending"
        static let onlyLate = "onlyLate"
        static let viewMode = "viewMode"
        static let mapZoom = "mapZoom"
        static let collapsedIDs = "collapsedIDs"
    }

    /// Quantidade máxima de níveis abaixo da raiz (raiz = nível 0).
    @Published var maxSubLevels: Int {
        didSet {
            let clamped = min(max(maxSubLevels, Self.subLevelsRange.lowerBound), Self.subLevelsRange.upperBound)
            if clamped != maxSubLevels { maxSubLevels = clamped; return }
            defaults.set(maxSubLevels, forKey: Key.maxSubLevels)
        }
    }
    @Published var showCompleted: Bool {
        didSet { defaults.set(showCompleted, forKey: Key.showCompleted) }
    }
    @Published var showPending: Bool {
        didSet { defaults.set(showPending, forKey: Key.showPending) }
    }
    /// Só itens atrasados em relação ao planejado (com os ancestrais para contexto).
    @Published var onlyLate: Bool {
        didSet { defaults.set(onlyLate, forKey: Key.onlyLate) }
    }
    @Published var viewMode: ViewMode {
        didSet { defaults.set(viewMode.rawValue, forKey: Key.viewMode) }
    }
    @Published var mapZoom: Double {
        didSet {
            let clamped = min(max(mapZoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
            if clamped != mapZoom { mapZoom = clamped; return }
            defaults.set(mapZoom, forKey: Key.mapZoom)
        }
    }
    /// Nós recolhidos no mapa (filhos ocultos).
    @Published var collapsedIDs: Set<UUID> {
        didSet { defaults.set(collapsedIDs.map(\.uuidString), forKey: Key.collapsedIDs) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let levels = defaults.object(forKey: Key.maxSubLevels) as? Int ?? Self.defaultMaxSubLevels
        maxSubLevels = min(max(levels, Self.subLevelsRange.lowerBound), Self.subLevelsRange.upperBound)
        showCompleted = defaults.object(forKey: Key.showCompleted) as? Bool ?? true
        showPending = defaults.object(forKey: Key.showPending) as? Bool ?? true
        onlyLate = defaults.object(forKey: Key.onlyLate) as? Bool ?? false
        viewMode = ViewMode(rawValue: defaults.string(forKey: Key.viewMode) ?? "") ?? .map
        let zoom = defaults.object(forKey: Key.mapZoom) as? Double ?? 1
        mapZoom = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let ids = defaults.stringArray(forKey: Key.collapsedIDs) ?? []
        collapsedIDs = Set(ids.compactMap(UUID.init(uuidString:)))
    }

    /// Um item passa no filtro rápido atual?
    func matchesFilter(_ item: TaskItem, now: Date = Date()) -> Bool {
        guard item.isDone ? showCompleted : showPending else { return false }
        return !onlyLate || item.isLate(at: now)
    }

    func toggleCollapsed(_ id: UUID) {
        if collapsedIDs.contains(id) { collapsedIDs.remove(id) } else { collapsedIDs.insert(id) }
    }

    func zoomIn() { mapZoom = (mapZoom + Self.zoomStep).rounded(toStep: Self.zoomStep) }
    func zoomOut() { mapZoom = (mapZoom - Self.zoomStep).rounded(toStep: Self.zoomStep) }
    func resetZoom() { mapZoom = 1 }
}

private extension Double {
    func rounded(toStep step: Double) -> Double {
        (self / step).rounded() * step
    }
}
