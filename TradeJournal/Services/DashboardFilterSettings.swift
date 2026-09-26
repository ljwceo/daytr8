import Foundation

/// De filters van het dashboard als waarde, zodat ze bewaard kunnen worden.
public struct DashboardFilterState: Codable, Equatable, Sendable {
    public var selectedAccountIDs: [UUID]
    public var period: String
    public var customStart: Date?
    public var customEnd: Date?
    public var symbolFilter: String?
    public var playbookID: UUID?
    public var confluenceID: UUID?
    public var includeBacktest: Bool

    public init(
        selectedAccountIDs: [UUID] = [],
        period: String = "all",
        customStart: Date? = nil,
        customEnd: Date? = nil,
        symbolFilter: String? = nil,
        playbookID: UUID? = nil,
        confluenceID: UUID? = nil,
        includeBacktest: Bool = false
    ) {
        self.selectedAccountIDs = selectedAccountIDs
        self.period = period
        self.customStart = customStart
        self.customEnd = customEnd
        self.symbolFilter = symbolFilter
        self.playbookID = playbookID
        self.confluenceID = confluenceID
        self.includeBacktest = includeBacktest
    }
}

/// Bewaart de dashboardfilters in `UserDefaults` (als JSON-tekst), zodat ze
/// een herstart en een app-update overleven. `defaults` is injecteerbaar
/// voor tests.
public final class DashboardFilterSettings {

    public static let key = "dashboard.filters"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `nil` als er nog niets bewaard is of de waarde onleesbaar is.
    public func load() -> DashboardFilterState? {
        guard let text = defaults.string(forKey: Self.key), let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DashboardFilterState.self, from: data)
    }

    public func save(_ state: DashboardFilterState) {
        guard let data = try? JSONEncoder().encode(state), let text = String(data: data, encoding: .utf8) else { return }
        defaults.set(text, forKey: Self.key)
    }
}
