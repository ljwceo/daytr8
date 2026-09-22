import Foundation

/// Exporteert trades naar een CSV-bestand (één rij per trade).
///
/// Het formaat is bewust machine-leesbaar (ISO 8601-tijden, punt als
/// decimaalteken) en wordt door de `TradeJournal`-preset van de CSV-import
/// weer ingelezen, zodat een export ook als eenvoudige migratie werkt.
/// Voor een volledige backup (incl. screenshots, journals, playbooks) is er
/// `BackupService`.
public struct CSVExportService {

    public static let headers: [String] = [
        "trade_id", "account", "symbol", "direction",
        "entry_time", "exit_time", "entry_price", "exit_price", "quantity",
        "stop_loss", "take_profit", "planned_risk",
        "commission", "fees", "gross_pnl", "net_pnl", "r_multiple",
        "session", "playbook", "confluences", "tags", "mistakes",
        "emotion_before", "emotion_after", "rating", "notes"
    ]

    public let statsService: StatsService

    public init(statsService: StatsService = StatsService()) {
        self.statsService = statsService
    }

    /// CSV-tekst voor `trades`, gesorteerd op entry-tijd (oud → nieuw).
    public func csv(for trades: [Trade]) -> String {
        let sorted = trades.sorted { $0.entryDate < $1.entryDate }
        return CSVWriter.write(headers: Self.headers, rows: sorted.map(row(for:)))
    }

    /// Schrijft de CSV naar een tijdelijk bestand en geeft de URL terug
    /// (voor de share sheet / Bestanden-app).
    public func exportFile(for trades: [Trade], now: Date = Date()) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TradeJournal-trades-\(Self.fileTimestamp(now)).csv")
        try Data(csv(for: trades).utf8).write(to: url, options: .atomic)
        return url
    }

    // MARK: - Intern

    func row(for trade: Trade) -> [String] {
        let metrics = statsService.metrics(for: trade)
        let execCommission = trade.executions.reduce(0) { $0 + $1.commission }
        let execFees = trade.executions.reduce(0) { $0 + $1.fees }
        let isOpen = metrics.outcome == .open

        // Bewust stap voor stap opgebouwd: één grote array-literal met veel
        // `??`/ternaries is traag voor de Swift type-checker.
        let gross: String = isOpen ? "" : Self.number(metrics.grossPnL)
        let net: String = isOpen ? "" : Self.number(metrics.netPnL)
        var rMultiple = ""
        if !isOpen, let r = metrics.rMultiple { rMultiple = Self.number(r) }

        var row: [String] = []
        row.reserveCapacity(Self.headers.count)
        row.append(trade.id.uuidString)
        row.append(trade.account?.name ?? "")
        row.append(trade.symbol)
        row.append(trade.direction.rawValue)
        row.append(Self.isoString(trade.entryDate))
        row.append(Self.optional(trade.exitDate, Self.isoString))
        row.append(Self.number(trade.entryPrice))
        row.append(Self.optional(trade.exitPrice, Self.number))
        row.append(Self.number(trade.quantity))
        row.append(Self.optional(trade.stopLoss, Self.number))
        row.append(Self.optional(trade.takeProfit, Self.number))
        row.append(Self.optional(trade.plannedRisk, Self.number))
        row.append(Self.number(trade.commission + execCommission))
        row.append(Self.number(trade.fees + execFees))
        row.append(gross)
        row.append(net)
        row.append(rMultiple)
        row.append(trade.session.displayName)
        row.append(trade.playbook?.name ?? "")
        row.append(trade.confluences.map(\.name).sorted().joined(separator: "; "))
        row.append(trade.tags.map(\.name).sorted().joined(separator: "; "))
        row.append(trade.mistakes.map(\.name).sorted().joined(separator: "; "))
        row.append(trade.emotionBefore)
        row.append(trade.emotionAfter)
        row.append(trade.rating > 0 ? String(trade.rating) : "")
        row.append(trade.notes)
        return row
    }

    private static func optional<Value>(_ value: Value?, _ format: (Value) -> String) -> String {
        guard let value else { return "" }
        return format(value)
    }

    static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Getal met punt als decimaalteken en zonder overbodige nullen.
    static func number(_ value: Double) -> String {
        let rounded = (value * 1_000_000).rounded() / 1_000_000
        if rounded == rounded.rounded() && abs(rounded) < 1e15 {
            return String(Int64(rounded))
        }
        var text = String(format: "%.6f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    static func fileTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: date)
    }
}
