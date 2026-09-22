import Foundation

/// Eén rij in een rapportage-tabblad: een groep (confluence, playbook, sessie, ...)
/// met de statistieken van de trades die daarin vallen.
public struct GroupResult: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let statistics: TradeStatistics
    public let colorHex: String?

    public init(id: String, label: String, statistics: TradeStatistics, colorHex: String? = nil) {
        self.id = id
        self.label = label
        self.statistics = statistics
        self.colorHex = colorHex
    }
}

/// Bucket voor de "per trade-duur"-rapportage.
public enum TradeDurationBucket: String, CaseIterable, Sendable {
    case under5m, m5to15, m15to30, m30to60, h1to2, h2to4, h4plus

    public var label: String {
        switch self {
        case .under5m: return "< 5 min"
        case .m5to15: return "5–15 min"
        case .m15to30: return "15–30 min"
        case .m30to60: return "30–60 min"
        case .h1to2: return "1–2 uur"
        case .h2to4: return "2–4 uur"
        case .h4plus: return "> 4 uur"
        }
    }

    public static func bucket(forSeconds seconds: TimeInterval) -> TradeDurationBucket {
        let minutes = seconds / 60
        switch minutes {
        case ..<5: return .under5m
        case 5..<15: return .m5to15
        case 15..<30: return .m15to30
        case 30..<60: return .m30to60
        case 60..<120: return .h1to2
        case 120..<240: return .h2to4
        default: return .h4plus
        }
    }
}

/// Groepeert al gefilterde trades op allerlei dimensies voor de Rapporten-tab
/// (`SPEC.md §7`): per confluence, per confluentiecombinatie, per playbook,
/// per symbool, per richting, per sessie, per dag van de week, per uur van de
/// dag, per trade-duur, per tag, per mistake, en emotie/rating tegenover
/// resultaat.
///
/// Alle methodes zijn puur (geen SwiftData-mutaties) en werken in één O(n)-pas
/// per dimensie over de meegegeven tradelijst.
public struct ReportAggregationService: Sendable {

    public let statsService: StatsService

    public init(statsService: StatsService = StatsService()) {
        self.statsService = statsService
    }

    private static let dutchWeekdayNames = [
        "Zondag", "Maandag", "Dinsdag", "Woensdag", "Donderdag", "Vrijdag", "Zaterdag",
    ]

    // MARK: - Generieke groepering

    /// Groepeert `trades` via `keys(trade)`. Een trade kan in meerdere groepen
    /// vallen (confluences, tags, mistakes) of in precies één (playbook, symbool, ...).
    /// Trades waarvoor `keys` een lege array teruggeeft, tellen nergens mee.
    private func group(
        _ trades: [Trade],
        keys: (Trade) -> [(id: String, label: String, colorHex: String?)]
    ) -> [GroupResult] {
        var buckets: [String: (label: String, colorHex: String?, trades: [Trade])] = [:]
        for trade in trades {
            for key in keys(trade) {
                buckets[key.id, default: (key.label, key.colorHex, [])].trades.append(trade)
            }
        }
        return buckets.map { id, bucket in
            GroupResult(id: id, label: bucket.label, statistics: statsService.statistics(for: bucket.trades), colorHex: bucket.colorHex)
        }
    }

    // MARK: - Confluences

    public func byConfluence(_ trades: [Trade]) -> [GroupResult] {
        group(trades) { trade in
            trade.confluences.map { (id: $0.id.uuidString, label: $0.name, colorHex: $0.colorHex) }
        }
    }

    /// Combinaties van confluences die samen op één trade voorkomen (bijv.
    /// "Sweep PDL + IFVG"), gerangschikt op expectancy — zo zie je welke
    /// combinaties echt werken. Combinaties met minder dan `minTradeCount`
    /// trades worden weggelaten (te weinig signaal).
    public func byConfluenceCombination(_ trades: [Trade], comboSize: Int = 2, minTradeCount: Int = 2) -> [GroupResult] {
        let results = group(trades) { trade in
            guard trade.confluences.count >= comboSize else { return [] }
            let sorted = trade.confluences.sorted { $0.name < $1.name }
            return combinations(sorted, size: comboSize).map { combo in
                let id = combo.map { $0.id.uuidString }.sorted().joined(separator: "|")
                let label = combo.map(\.name).joined(separator: " + ")
                return (id: id, label: label, colorHex: nil)
            }
        }
        return results
            .filter { $0.statistics.tradeCount >= minTradeCount }
            .sorted { $0.statistics.expectancy > $1.statistics.expectancy }
    }

    private func combinations<T>(_ array: [T], size: Int) -> [[T]] {
        guard size > 0 else { return [[]] }
        guard array.count >= size else { return [] }
        if size == array.count { return [array] }
        var result: [[T]] = []
        for i in 0..<array.count {
            let rest = Array(array[(i + 1)...])
            for combo in combinations(rest, size: size - 1) {
                result.append([array[i]] + combo)
            }
        }
        return result
    }

    // MARK: - Playbook, symbool, richting, sessie

    public func byPlaybook(_ trades: [Trade]) -> [GroupResult] {
        group(trades) { trade in
            guard let playbook = trade.playbook else { return [] }
            return [(id: playbook.id.uuidString, label: playbook.name, colorHex: playbook.colorHex)]
        }
    }

    public func bySymbol(_ trades: [Trade]) -> [GroupResult] {
        group(trades) { trade in [(id: trade.symbol, label: trade.symbol, colorHex: nil)] }
    }

    public func byDirection(_ trades: [Trade]) -> [GroupResult] {
        group(trades) { trade in [(id: trade.direction.rawValue, label: trade.direction.displayName, colorHex: nil)] }
    }

    public func bySession(_ trades: [Trade]) -> [GroupResult] {
        group(trades) { trade in [(id: trade.session.rawValue, label: trade.session.displayName, colorHex: nil)] }
    }

    // MARK: - Dag van de week / uur van de dag / duur

    /// Gesorteerd maandag → zondag, ongeacht `calendar.firstWeekday`.
    public func byDayOfWeek(_ trades: [Trade], calendar: Calendar = .current) -> [GroupResult] {
        let results = group(trades) { trade in
            let date = trade.exitDate ?? trade.entryDate
            let weekday = calendar.component(.weekday, from: date)  // 1 = zondag ... 7 = zaterdag
            return [(id: String(weekday), label: Self.dutchWeekdayNames[weekday - 1], colorHex: nil)]
        }
        let mondayFirstOrder: [String: Int] = ["2": 0, "3": 1, "4": 2, "5": 3, "6": 4, "7": 5, "1": 6]
        return results.sorted { (mondayFirstOrder[$0.id] ?? 0) < (mondayFirstOrder[$1.id] ?? 0) }
    }

    public func byHourOfDay(_ trades: [Trade], calendar: Calendar = .current) -> [GroupResult] {
        let results = group(trades) { trade in
            let hour = calendar.component(.hour, from: trade.entryDate)
            return [(id: String(format: "%02d", hour), label: String(format: "%02d:00", hour), colorHex: nil)]
        }
        return results.sorted { $0.id < $1.id }
    }

    public func byDuration(_ trades: [Trade]) -> [GroupResult] {
        let results = group(trades) { trade in
            guard let seconds = trade.durationSeconds, seconds >= 0 else { return [] }
            let bucket = TradeDurationBucket.bucket(forSeconds: seconds)
            return [(id: bucket.rawValue, label: bucket.label, colorHex: nil)]
        }
        let order = TradeDurationBucket.allCases.map(\.rawValue)
        return results.sorted { (order.firstIndex(of: $0.id) ?? 0) < (order.firstIndex(of: $1.id) ?? 0) }
    }

    // MARK: - Tags & mistakes

    public func byTag(_ trades: [Trade]) -> [GroupResult] {
        group(trades) { trade in trade.tags.map { (id: $0.id.uuidString, label: $0.name, colorHex: $0.colorHex) } }
    }

    /// Netto P&L per mistake laat direct zien hoeveel elke fout kost.
    public func byMistake(_ trades: [Trade]) -> [GroupResult] {
        group(trades) { trade in trade.mistakes.map { (id: $0.id.uuidString, label: $0.name, colorHex: $0.colorHex) } }
    }

    // MARK: - Emotie & rating vs. resultaat

    public func byEmotionBefore(_ trades: [Trade]) -> [GroupResult] {
        group(trades) { trade in
            let value = trade.emotionBefore.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return [] }
            return [(id: value.lowercased(), label: value, colorHex: nil)]
        }
    }

    public func byEmotionAfter(_ trades: [Trade]) -> [GroupResult] {
        group(trades) { trade in
            let value = trade.emotionAfter.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return [] }
            return [(id: value.lowercased(), label: value, colorHex: nil)]
        }
    }

    /// Gesorteerd 1 → 5 sterren. Trades zonder rating (0) tellen niet mee.
    public func byRating(_ trades: [Trade]) -> [GroupResult] {
        let results = group(trades) { trade in
            guard trade.rating > 0 else { return [] }
            return [(id: String(trade.rating), label: "\(trade.rating) ★", colorHex: nil)]
        }
        return results.sorted { $0.id < $1.id }
    }
}
