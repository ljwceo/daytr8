import Foundation

/// De vijf top-level tabs van `RootTabView`. Eén bron van waarheid voor de
/// tabbalk én de uitleg in de onboarding.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case calendar
    case trades
    case reports
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .calendar: return "Kalender"
        case .trades: return "Trades"
        case .reports: return "Rapporten"
        case .more: return "Meer"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "chart.line.uptrend.xyaxis"
        case .calendar: return "calendar"
        case .trades: return "list.bullet.rectangle"
        case .reports: return "chart.bar.doc.horizontal"
        case .more: return "ellipsis.circle"
        }
    }

    /// Korte uitleg voor de navigatiestap van de onboarding.
    var onboardingDescription: String {
        switch self {
        case .dashboard: return AppStrings.Onboarding.tabDashboard
        case .calendar: return AppStrings.Onboarding.tabCalendar
        case .trades: return AppStrings.Onboarding.tabTrades
        case .reports: return AppStrings.Onboarding.tabReports
        case .more: return AppStrings.Onboarding.tabMore
        }
    }
}
