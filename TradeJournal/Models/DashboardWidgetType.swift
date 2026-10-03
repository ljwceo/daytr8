import Foundation

/// Alle widgettypes van het dashboard. De ruwe waarde staat in
/// `DashboardWidget.typeRaw` en in de backup; nooit hernoemen.
///
/// Naam, icoon, standaardgrootte en instellingenscherm per type staan in de
/// registry (`DashboardWidgetRegistry`); een nieuw type = een case hier plus
/// een definitie daar.
public enum DashboardWidgetType: String, Codable, CaseIterable, Identifiable, Sendable {
    case yearHeatmap = "year_heatmap"
    case statistic
    case equityCurve = "equity_curve"
    case dailyPnL = "daily_pnl"
    case drawdown
    case miniCalendar = "mini_calendar"
    case topFlop = "top_flop"
    case rHistogram = "r_histogram"
    case goalProgress = "goal_progress"
    case ruleStreak = "rule_streak"
    case recentTrades = "recent_trades"
    case note
    case backupStatus = "backup_status"
    case tradingScore = "trading_score"

    public var id: String { rawValue }
}

/// Grootte van een widget: klein = halve breedte, groot = volle breedte.
public enum WidgetSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small
    case large

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .small: return "Klein (halve breedte)"
        case .large: return "Groot (volle breedte)"
        }
    }

    public var toggled: WidgetSize { self == .small ? .large : .small }
}
