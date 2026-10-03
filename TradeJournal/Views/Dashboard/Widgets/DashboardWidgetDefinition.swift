import SwiftUI

/// Welke instellingen een widgettype heeft; het standaard
/// instellingenscherm toont alleen die secties.
struct WidgetSettingsOptions: OptionSet {
    let rawValue: Int

    /// Periode (week/maand/jaar/alles/aangepast of zoals dashboard).
    static let period = WidgetSettingsOptions(rawValue: 1 << 0)
    /// Account(s).
    static let accounts = WidgetSettingsOptions(rawValue: 1 << 1)
    /// Kengetal van de statistiekkaart.
    static let metric = WidgetSettingsOptions(rawValue: 1 << 2)
    /// Wat de heatmap-kleur toont.
    static let heatmapMetric = WidgetSettingsOptions(rawValue: 1 << 3)
    /// Dimensie (symbool, confluence, playbook, sessie).
    static let dimension = WidgetSettingsOptions(rawValue: 1 << 4)
    /// Aantal regels.
    static let itemCount = WidgetSettingsOptions(rawValue: 1 << 5)
}

/// Eén widgettype op het dashboard.
///
/// Elk type meldt zich aan in `DashboardWidgetRegistry` met naam, icoon,
/// standaardgrootte, instellingen en zijn weergave. Een nieuw type
/// toevoegen = een case in `DashboardWidgetType` + een struct die dit
/// protocol volgt + één regel in de registry. Het dashboard, de
/// bibliotheek, het instellingenscherm en de backup werken dan vanzelf.
@MainActor
protocol DashboardWidgetDefinition {
    var type: DashboardWidgetType { get }
    /// Naam in de bibliotheek en standaardtitel.
    var title: String { get }
    /// SF Symbol.
    var systemImage: String { get }
    /// Eén zin uitleg in de bibliotheek.
    var summary: String { get }
    var defaultSize: WidgetSize { get }
    /// Groottes die het type ondersteunt (minstens één).
    var supportedSizes: [WidgetSize] { get }
    var options: WidgetSettingsOptions { get }
    /// Instellingen van een nieuw toegevoegde widget.
    var defaultSettings: WidgetSettings { get }

    /// Titel in de kop als de gebruiker geen eigen titel heeft gekozen.
    func defaultTitle(for settings: WidgetSettings) -> String
    /// De inhoud van de widget (zonder kaart en kop; die tekent de container).
    func makeContent(_ context: WidgetRenderContext) -> AnyView
    /// Het instellingenscherm (secties binnen een `Form`).
    func makeSettingsView(_ settings: Binding<WidgetSettings>, accounts: [Account]) -> AnyView
}

extension DashboardWidgetDefinition {
    var supportedSizes: [WidgetSize] { WidgetSize.allCases }
    var defaultSettings: WidgetSettings { WidgetSettings() }

    func defaultTitle(for settings: WidgetSettings) -> String { title }

    /// Standaard: de secties die bij `options` horen.
    func makeSettingsView(_ settings: Binding<WidgetSettings>, accounts: [Account]) -> AnyView {
        AnyView(StandardWidgetSettingsSections(settings: settings, options: options, accounts: accounts))
    }

    /// Titel in de kop: eigen titel of de standaardtitel.
    func displayTitle(for settings: WidgetSettings) -> String {
        let custom = settings.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? defaultTitle(for: settings) : custom
    }

    /// Ondertitel in de kop: de periode als die afwijkt van het dashboard.
    func subtitle(for settings: WidgetSettings) -> String? {
        guard options.contains(.period), settings.period != .dashboard else { return nil }
        if settings.period == .custom, let range = settings.customRange {
            return "\(range.lowerBound.formatted(date: .abbreviated, time: .omitted)) – \(range.upperBound.formatted(date: .abbreviated, time: .omitted))"
        }
        return settings.period.displayName
    }

    /// De grootte die getoond wordt (een niet-ondersteunde valt terug op de standaard).
    func effectiveSize(_ size: WidgetSize) -> WidgetSize {
        supportedSizes.contains(size) ? size : defaultSize
    }
}

/// Alle widgettypes, in de volgorde van de bibliotheek.
@MainActor
enum DashboardWidgetRegistry {

    static let definitions: [any DashboardWidgetDefinition] = [
        YearHeatmapWidgetDefinition(),
        StatisticWidgetDefinition(),
        EquityCurveWidgetDefinition(),
        DailyPnLWidgetDefinition(),
        DrawdownWidgetDefinition(),
        MiniCalendarWidgetDefinition(),
        TopFlopWidgetDefinition(),
        RHistogramWidgetDefinition(),
        GoalProgressWidgetDefinition(),
        RuleStreakWidgetDefinition(),
        RecentTradesWidgetDefinition(),
        TradingScoreWidgetDefinition(),
        NoteWidgetDefinition(),
        BackupStatusWidgetDefinition()
    ]

    static func definition(for type: DashboardWidgetType) -> (any DashboardWidgetDefinition)? {
        definitions.first { $0.type == type }
    }

    /// Definitie bij een opgeslagen widget; `nil` voor een onbekend type.
    static func definition(for widget: DashboardWidget) -> (any DashboardWidgetDefinition)? {
        widget.type.flatMap { definition(for: $0) }
    }
}

/// Alles wat een widget nodig heeft om zichzelf te tekenen.
struct WidgetRenderContext {
    let widgetID: UUID
    let size: WidgetSize
    let settings: WidgetSettings
    /// `settings` als tekst, één keer per render gemaakt (sleutel voor de cache).
    let settingsKey: String
    /// Alle trades (ongefilterd); de widget filtert via `filteredTrades`.
    let allTrades: [Trade]
    let accounts: [Account]
    let rules: [DailyRule]
    let journals: [DailyJournal]
    let ruleChecks: [DailyRuleCheck]
    /// Filters van het dashboard.
    let baseFilter: DashboardFilterState
    /// Sleutel van `baseFilter` voor de cache.
    let baseFilterKey: String
    /// Grafiekdata, doelen en trading score (zelfde berekeningen als voorheen).
    let dashboardModel: DashboardViewModel
    let dataService: WidgetDataService
    let cache: WidgetComputationCache
    let cacheVersion: String
    /// In de bibliotheek: niet interactief.
    let isPreview: Bool
    let onOpenDay: (Date) -> Void
    let onEditSettings: () -> Void

    /// Filters van deze widget (dashboard + eigen periode/accounts).
    var filter: DashboardFilterState {
        dataService.effectiveFilter(base: baseFilter, settings: settings)
    }

    /// Trades volgens de filters van deze widget (gecachet).
    var filteredTrades: [Trade] {
        cached("trades") { dataService.trades(allTrades, matching: filter) }
    }

    /// Valuta van het (eerste) gekozen account, anders van het eerste account.
    var currency: String {
        let selected = filter.selectedAccountIDs
        return accounts.first { selected.contains($0.id) }?.currency ?? accounts.first?.currency ?? "USD"
    }

    func cached<T>(_ name: String, compute: () -> T) -> T {
        cache.value("\(widgetID.uuidString)|\(settingsKey)|\(baseFilterKey)|\(name)", version: cacheVersion, compute: compute)
    }
}

/// Opmaak die meerdere widgets delen.
enum WidgetFormat {
    static func money(_ value: Double, _ currency: String) -> String {
        value.formatted(.currency(code: currency).precision(.fractionLength(0)))
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    static func rMultiple(_ value: Double) -> String {
        String(format: "%+.2fR", value)
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

/// Lege staat binnen een widget.
struct WidgetEmptyStateView: View {
    let text: String
    var minHeight: CGFloat = 60

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: minHeight)
    }
}
