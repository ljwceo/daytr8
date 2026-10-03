import Foundation

/// Instellingen van één dashboardwidget, als JSON bewaard in
/// `DashboardWidget.settingsJSON`.
///
/// Eén gedeelde struct voor alle types; welke velden een type gebruikt staat
/// in zijn definitie (`DashboardWidgetDefinition.options`). Het decoderen is
/// tolerant: ontbrekende of onbekende waardes (bijv. uit een nieuwere
/// app-versie) vallen terug op de standaard in plaats van de hele widget
/// onbruikbaar te maken.
public struct WidgetSettings: Codable, Equatable, Sendable {

    /// Periode van de widget. `dashboard` = volg de periodefilter van het dashboard.
    public enum Period: String, Codable, CaseIterable, Identifiable, Sendable {
        case dashboard
        case week
        case month
        case year
        case all
        case custom

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .dashboard: return "Zoals dashboard"
            case .week: return "Deze week"
            case .month: return "Deze maand"
            case .year: return "Dit jaar"
            case .all: return "Alles"
            case .custom: return "Aangepast"
            }
        }

        /// De bijbehorende dashboardperiode; `nil` voor `dashboard` (volgen).
        public var dashboardPeriod: DashboardViewModel.Period? {
            switch self {
            case .dashboard: return nil
            case .week: return .thisWeek
            case .month: return .thisMonth
            case .year: return .thisYear
            case .all: return .all
            case .custom: return .custom
            }
        }
    }

    /// Kengetal van de statistiekkaart.
    public enum Metric: String, Codable, CaseIterable, Identifiable, Sendable {
        case netPnL = "net_pnl"
        case winRate = "win_rate"
        case profitFactor = "profit_factor"
        case expectancy
        case averageR = "average_r"
        case maxDrawdown = "max_drawdown"
        case tradeCount = "trade_count"
        case streak
        case averageWinLoss = "average_win_loss"
        case largestWinLoss = "largest_win_loss"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .netPnL: return "Netto P&L"
            case .winRate: return "Win rate"
            case .profitFactor: return "Profit factor"
            case .expectancy: return "Expectancy"
            case .averageR: return "Gem. R"
            case .maxDrawdown: return "Max drawdown"
            case .tradeCount: return "Aantal trades"
            case .streak: return "Streak"
            case .averageWinLoss: return "Gem. winst / verlies"
            case .largestWinLoss: return "Grootste winst / verlies"
            }
        }

        /// `true` als een lagere waarde beter is (voor de kleur van de verandering).
        public var lowerIsBetter: Bool { self == .maxDrawdown }
    }

    /// Wat de kleur van de jaar-heatmap toont.
    public enum HeatmapMetric: String, Codable, CaseIterable, Identifiable, Sendable {
        case netPnL = "net_pnl"
        case tradeCount = "trade_count"
        case winRate = "win_rate"
        case rMultiple = "r_multiple"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .netPnL: return "Netto P&L"
            case .tradeCount: return "Aantal trades"
            case .winRate: return "Win rate"
            case .rMultiple: return "Behaalde R"
            }
        }
    }

    /// Dimensie van de top/flop-lijst.
    public enum Dimension: String, Codable, CaseIterable, Identifiable, Sendable {
        case symbol
        case confluence
        case playbook
        case session

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .symbol: return "Symbolen"
            case .confluence: return "Confluences"
            case .playbook: return "Playbooks"
            case .session: return "Sessies"
            }
        }
    }

    /// Eigen titel; `nil` of leeg = de naam van het widgettype.
    public var customTitle: String?
    public var period: Period
    public var customStart: Date?
    public var customEnd: Date?
    /// Leeg = de accountfilter van het dashboard.
    public var accountIDs: [UUID]
    public var metric: Metric
    public var heatmapMetric: HeatmapMetric
    public var dimension: Dimension
    /// Aantal regels (top/flop per kant, recente trades).
    public var itemCount: Int
    /// Tekst van de notitiewidget.
    public var noteText: String

    public init(
        customTitle: String? = nil,
        period: Period = .dashboard,
        customStart: Date? = nil,
        customEnd: Date? = nil,
        accountIDs: [UUID] = [],
        metric: Metric = .netPnL,
        heatmapMetric: HeatmapMetric = .netPnL,
        dimension: Dimension = .symbol,
        itemCount: Int = 3,
        noteText: String = ""
    ) {
        self.customTitle = customTitle
        self.period = period
        self.customStart = customStart
        self.customEnd = customEnd
        self.accountIDs = accountIDs
        self.metric = metric
        self.heatmapMetric = heatmapMetric
        self.dimension = dimension
        self.itemCount = itemCount
        self.noteText = noteText
    }

    private enum CodingKeys: String, CodingKey {
        case customTitle, period, customStart, customEnd, accountIDs, metric, heatmapMetric, dimension, itemCount, noteText
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = WidgetSettings()
        customTitle = try? container.decodeIfPresent(String.self, forKey: .customTitle)
        period = Self.decodeEnum(Period.self, .period, in: container) ?? defaults.period
        customStart = try? container.decodeIfPresent(Date.self, forKey: .customStart)
        customEnd = try? container.decodeIfPresent(Date.self, forKey: .customEnd)
        accountIDs = (try? container.decodeIfPresent([UUID].self, forKey: .accountIDs)) ?? defaults.accountIDs
        metric = Self.decodeEnum(Metric.self, .metric, in: container) ?? defaults.metric
        heatmapMetric = Self.decodeEnum(HeatmapMetric.self, .heatmapMetric, in: container) ?? defaults.heatmapMetric
        dimension = Self.decodeEnum(Dimension.self, .dimension, in: container) ?? defaults.dimension
        itemCount = (try? container.decodeIfPresent(Int.self, forKey: .itemCount)) ?? defaults.itemCount
        noteText = (try? container.decodeIfPresent(String.self, forKey: .noteText)) ?? defaults.noteText
    }

    private static func decodeEnum<E: RawRepresentable>(_ type: E.Type, _ key: CodingKeys, in container: KeyedDecodingContainer<CodingKeys>) -> E? where E.RawValue == String {
        guard let raw = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
        return E(rawValue: raw)
    }

    // MARK: - JSON

    /// Als JSON-tekst (voor `DashboardWidget.settingsJSON`).
    public var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    /// Leest JSON-tekst; onleesbaar of leeg = standaardinstellingen.
    public static func from(json: String) -> WidgetSettings {
        guard let data = json.data(using: .utf8), let settings = try? JSONDecoder().decode(WidgetSettings.self, from: data) else {
            return WidgetSettings()
        }
        return settings
    }

    /// De gekozen aangepaste periode, als begin en eind geldig zijn.
    public var customRange: ClosedRange<Date>? {
        guard let customStart, let customEnd, customStart <= customEnd else { return nil }
        return customStart...customEnd
    }
}
