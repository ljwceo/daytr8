import Foundation
import SwiftData

/// Een melding bij een herkende trade in het controlescherm.
public struct MT5ImportIssue: Equatable, Hashable, Sendable {

    public enum Severity: Int, Comparable, Sendable {
        /// Laten controleren; importeren mag.
        case warning
        /// Eerst corrigeren; zo kan de trade niet geïmporteerd worden.
        case error

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public enum Kind: String, Sendable {
        case missing
        case invalid
        case truncated
        case lowConfidence = "low_confidence"
        case unknownSymbol = "unknown_symbol"
        case pnlMismatch = "pnl_mismatch"
        case futureDate = "future_date"
        case duplicateExisting = "duplicate_existing"
        case duplicateInBatch = "duplicate_in_batch"
    }

    public let kind: Kind
    public let severity: Severity
    /// Het veld waar het om gaat (`nil` = de hele trade).
    public let field: MT5ParsedTrade.Field?
    public let message: String

    public init(_ kind: Kind, _ severity: Severity, field: MT5ParsedTrade.Field? = nil, _ message: String) {
        self.kind = kind
        self.severity = severity
        self.field = field
        self.message = message
    }
}

/// Eén regel in het controlescherm: een herkende trade, bewerkbaar.
public struct MT5ImportRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// Index van de screenshot waar de trade op staat (wordt de bijlage).
    public var screenshotIndex: Int
    public var symbol: String
    public var direction: TradeDirection?
    public var volume: Double?
    public var entryPrice: Double?
    public var exitPrice: Double?
    public var closeTime: Date?
    public var pnl: Double?
    /// Onzeker gelezen velden (lage OCR-zekerheid of correctie).
    public var uncertainFields: Set<MT5ParsedTrade.Field>
    public var isTruncated: Bool
    public var sourceLines: [String]

    public var isSelected: Bool
    /// Velden die de gebruiker heeft aangepast (telt als "gecorrigeerd").
    public var editedFields: Set<MT5ParsedTrade.Field>
    /// Onzeker gelezen velden die de gebruiker ongewijzigd heeft goedgekeurd.
    public var confirmedFields: Set<MT5ParsedTrade.Field>
    public var accountID: UUID?
    public var playbookID: UUID?
    public var tagID: UUID?

    /// Ingevuld door `validate`.
    public var isDuplicateOfExisting: Bool
    public var issues: [MT5ImportIssue]

    public init(
        id: UUID = UUID(),
        screenshotIndex: Int = 0,
        parsed: MT5ParsedTrade
    ) {
        self.id = id
        self.screenshotIndex = screenshotIndex
        self.symbol = parsed.symbol ?? ""
        self.direction = parsed.direction
        self.volume = parsed.volume
        self.entryPrice = parsed.entryPrice
        self.exitPrice = parsed.exitPrice
        self.closeTime = parsed.closeTime
        self.pnl = parsed.pnl
        self.uncertainFields = parsed.uncertainFields
        self.isTruncated = parsed.isTruncated
        self.sourceLines = parsed.sourceLines
        self.isSelected = false
        self.editedFields = []
        self.confirmedFields = []
        self.isDuplicateOfExisting = false
        self.issues = []
    }

    public var isEdited: Bool { !editedFields.isEmpty }
    public var hasErrors: Bool { issues.contains { $0.severity == .error } }

    /// Velden met een melding (voor de markering in de tabel).
    public func issues(for field: MT5ParsedTrade.Field) -> [MT5ImportIssue] {
        issues.filter { $0.field == field }
    }

    public func hasValue(_ field: MT5ParsedTrade.Field) -> Bool {
        switch field {
        case .symbol: return !symbol.trimmingCharacters(in: .whitespaces).isEmpty
        case .direction: return direction != nil
        case .volume: return volume != nil
        case .entryPrice: return entryPrice != nil
        case .exitPrice: return exitPrice != nil
        case .closeTime: return closeTime != nil
        case .pnl: return pnl != nil
        }
    }

    /// Sleutel voor duplicaatdetectie: symbool + sluittijd + prijzen.
    public var duplicateKey: String? {
        guard let closeTime, let entryPrice, let exitPrice, hasValue(.symbol) else { return nil }
        return MT5ScreenshotImportService.duplicateKey(symbol: symbol, closeTime: closeTime, entryPrice: entryPrice, exitPrice: exitPrice)
    }
}

/// Resultaat van een import, voor de samenvatting.
public struct MT5ImportSummary: Equatable, Sendable {
    public var imported: Int
    /// Overgeslagen omdat de trade al in het journal stond.
    public var skippedExisting: Int
    /// Dubbel op de screenshots (bij doorscrollen) en samengevoegd.
    public var mergedOnScreenshots: Int
    /// Geïmporteerde trades waarin iets met de hand is gecorrigeerd.
    public var corrected: Int
    /// Herkend maar niet aangevinkt (en geen duplicaat).
    public var notSelected: Int

    public var skippedAsDuplicate: Int { skippedExisting + mergedOnScreenshots }
}

/// Bulk-import van trades vanaf MT5-screenshots: samenvoegen over meerdere
/// screenshots, duplicaatdetectie (ook tegen het journal), controles en
/// opslaan. Puur op waardes en een `ModelContext`, zonder UI.
public struct MT5ScreenshotImportService {

    /// Wat de controles moeten weten over het bestaande journal.
    public struct ValidationContext: Sendable {
        /// Bekende symbolen (instrumenten, presets, eerdere trades), hoofdletters.
        public var knownSymbols: Set<String>
        /// Waarde van 1 punt koersbeweging × 1 lot per symbool (tickValue / tickSize).
        public var pointValues: [String: Double]
        /// Duplicaatsleutels van bestaande trades.
        public var existingKeys: Set<String>
        public var now: Date

        public init(knownSymbols: Set<String> = [], pointValues: [String: Double] = [:], existingKeys: Set<String> = [], now: Date = Date()) {
            self.knownSymbols = knownSymbols
            self.pointValues = pointValues
            self.existingKeys = existingKeys
            self.now = now
        }
    }

    /// Een sluittijd zoveel na "nu" geldt als in de toekomst (klokverschil).
    public static let futureTolerance: TimeInterval = 120

    public let statsService: StatsService

    public init(statsService: StatsService = StatsService()) {
        self.statsService = statsService
    }

    // MARK: - Context

    public static func makeContext(existingTrades: [Trade], instruments: [Instrument], now: Date = Date()) -> ValidationContext {
        var known = Set(InstrumentPresets.all.map { $0.symbol.uppercased() })
        var pointValues: [String: Double] = [:]
        for preset in InstrumentPresets.all where preset.tickSize > 0 {
            pointValues[preset.symbol.uppercased()] = preset.tickValue / preset.tickSize
        }
        for instrument in instruments {
            let symbol = instrument.symbol.uppercased()
            known.insert(symbol)
            if instrument.tickSize > 0 { pointValues[symbol] = instrument.tickValue / instrument.tickSize }
        }
        var keys = Set<String>()
        for trade in existingTrades {
            known.insert(trade.symbol.uppercased())
            guard let exitDate = trade.exitDate, let exitPrice = trade.exitPrice else { continue }
            keys.insert(duplicateKey(symbol: trade.symbol, closeTime: exitDate, entryPrice: trade.entryPrice, exitPrice: exitPrice))
        }
        return ValidationContext(knownSymbols: known, pointValues: pointValues, existingKeys: keys, now: now)
    }

    /// Symbool + sluittijd (op de seconde) + entry- en exitprijs.
    public static func duplicateKey(symbol: String, closeTime: Date, entryPrice: Double, exitPrice: Double) -> String {
        [
            symbol.trimmingCharacters(in: .whitespaces).uppercased(),
            String(Int(closeTime.timeIntervalSince1970.rounded())),
            String(format: "%.5f", entryPrice),
            String(format: "%.5f", exitPrice)
        ].joined(separator: "|")
    }

    // MARK: - Samenvoegen

    /// Zet de herkende trades van alle screenshots (in volgorde) om naar
    /// regels voor het controlescherm. Dezelfde trade op twee screenshots
    /// (doorscrollen) wordt samengevoegd; een afgekapte trade die elders
    /// volledig staat valt weg. Daarna gecontroleerd met `context`.
    public func prepare(_ screenshots: [[MT5ParsedTrade]], context: ValidationContext) -> (rows: [MT5ImportRow], merged: Int) {
        var rows: [MT5ImportRow] = []
        var merged = 0
        var incomplete: [MT5ImportRow] = []

        for (index, trades) in screenshots.enumerated() {
            for parsed in trades {
                let row = MT5ImportRow(screenshotIndex: index, parsed: parsed)
                guard row.duplicateKey != nil else {
                    incomplete.append(row)
                    continue
                }
                if let existing = rows.firstIndex(where: { $0.duplicateKey == row.duplicateKey && Self.isCompatible($0, row) }) {
                    rows[existing] = Self.combine(rows[existing], row)
                    merged += 1
                } else {
                    rows.append(row)
                }
            }
        }

        // Afgekapte stukken die bij een volledige trade horen, vallen weg.
        for row in incomplete {
            if rows.contains(where: { Self.isFragment(row, of: $0) }) {
                merged += 1
            } else {
                rows.append(row)
            }
        }

        var validated = validate(rows, context: context)
        for index in validated.indices {
            validated[index].isSelected = Self.isSelectedByDefault(validated[index])
        }
        return (validated, merged)
    }

    /// Twee lezingen van dezelfde trade spreken elkaar niet tegen.
    static func isCompatible(_ a: MT5ImportRow, _ b: MT5ImportRow) -> Bool {
        func same(_ x: Double?, _ y: Double?) -> Bool {
            guard let x, let y else { return true }
            return abs(x - y) < 0.000_001
        }
        let directionOK = a.direction == nil || b.direction == nil || a.direction == b.direction
        return directionOK && same(a.volume, b.volume) && same(a.pnl, b.pnl)
    }

    /// Vult ontbrekende velden aan; een veld is alleen nog onzeker als het in
    /// geen van beide lezingen zeker was.
    static func combine(_ a: MT5ImportRow, _ b: MT5ImportRow) -> MT5ImportRow {
        var result = a
        if result.direction == nil { result.direction = b.direction }
        if result.volume == nil { result.volume = b.volume }
        if result.pnl == nil { result.pnl = b.pnl }
        var uncertain = Set<MT5ParsedTrade.Field>()
        for field in MT5ParsedTrade.Field.allCases {
            let aUnsure = !a.hasValue(field) || a.uncertainFields.contains(field)
            let bUnsure = !b.hasValue(field) || b.uncertainFields.contains(field)
            if aUnsure && bUnsure && result.hasValue(field) { uncertain.insert(field) }
        }
        result.uncertainFields = uncertain
        result.isTruncated = a.isTruncated && b.isTruncated
        return result
    }

    /// `part` is een afgekapt stuk van `full`: alle bekende velden kloppen.
    static func isFragment(_ part: MT5ImportRow, of full: MT5ImportRow) -> Bool {
        guard full.duplicateKey != nil else { return false }
        var matchedAny = false
        func check(_ x: Double?, _ y: Double?) -> Bool {
            guard let x else { return true }
            matchedAny = true
            return y.map { abs($0 - x) < 0.000_001 } ?? false
        }
        if part.hasValue(.symbol) {
            matchedAny = true
            guard part.symbol.uppercased() == full.symbol.uppercased() else { return false }
        }
        if let direction = part.direction {
            matchedAny = true
            guard direction == full.direction else { return false }
        }
        if let closeTime = part.closeTime {
            matchedAny = true
            guard let fullClose = full.closeTime, abs(fullClose.timeIntervalSince(closeTime)) < 1 else { return false }
        }
        guard check(part.volume, full.volume), check(part.pnl, full.pnl),
              check(part.entryPrice, full.entryPrice), check(part.exitPrice, full.exitPrice) else { return false }
        // Minstens iets wat de trade echt onderscheidt (P&L, prijzen of tijd).
        let distinctive = part.pnl != nil || part.entryPrice != nil || part.closeTime != nil
        return matchedAny && distinctive
    }

    /// Standaard aangevinkt: geen fouten, geen duplicaat en geen melding die
    /// echt gecontroleerd moet worden (alleen "onbekend symbool" mag).
    public static func isSelectedByDefault(_ row: MT5ImportRow) -> Bool {
        !row.issues.contains { $0.severity == .error || $0.kind != .unknownSymbol }
    }

    // MARK: - Controles

    /// Berekent per regel de meldingen en of hij al in het journal staat.
    public func validate(_ rows: [MT5ImportRow], context: ValidationContext) -> [MT5ImportRow] {
        let batchValues = Self.batchPointValues(rows)
        var seenKeys = Set<String>()
        return rows.map { original -> MT5ImportRow in
            var row = original
            var issues: [MT5ImportIssue] = []

            for field in MT5ParsedTrade.Field.allCases where !row.hasValue(field) {
                issues.append(MT5ImportIssue(.missing, .error, field: field, "\(field.displayName) ontbreekt"))
            }
            if row.isTruncated && issues.contains(where: { $0.kind == .missing }) {
                issues.append(MT5ImportIssue(.truncated, .error, "Afgekapt of onvolledig gelezen: vul aan of verwijder"))
            }

            let symbol = row.symbol.trimmingCharacters(in: .whitespaces).uppercased()
            if row.hasValue(.symbol) && !Self.isPlausibleSymbol(symbol) {
                issues.append(MT5ImportIssue(.invalid, .error, field: .symbol, "Symbool onleesbaar"))
            }
            if let volume = row.volume, volume <= 0 {
                issues.append(MT5ImportIssue(.invalid, .error, field: .volume, "Volume moet groter dan 0 zijn"))
            }
            if let entry = row.entryPrice, entry <= 0 {
                issues.append(MT5ImportIssue(.invalid, .error, field: .entryPrice, "Entry-prijs moet groter dan 0 zijn"))
            }
            if let exit = row.exitPrice, exit <= 0 {
                issues.append(MT5ImportIssue(.invalid, .error, field: .exitPrice, "Exit-prijs moet groter dan 0 zijn"))
            }

            for field in MT5ParsedTrade.Field.allCases where row.uncertainFields.contains(field) && !row.editedFields.contains(field) && !row.confirmedFields.contains(field) && row.hasValue(field) {
                issues.append(MT5ImportIssue(.lowConfidence, .warning, field: field, "\(field.displayName) onzeker gelezen"))
            }

            if row.hasValue(.symbol), Self.isPlausibleSymbol(symbol), !context.knownSymbols.contains(symbol) {
                issues.append(MT5ImportIssue(.unknownSymbol, .warning, field: .symbol, "Onbekend symbool \(symbol)"))
            }

            if let closeTime = row.closeTime, closeTime > context.now.addingTimeInterval(Self.futureTolerance) {
                issues.append(MT5ImportIssue(.futureDate, .warning, field: .closeTime, "Sluittijd ligt in de toekomst"))
            }

            if let message = pnlMismatch(row, context: context, batchValues: batchValues) {
                issues.append(MT5ImportIssue(.pnlMismatch, .warning, field: .pnl, message))
            }

            row.isDuplicateOfExisting = false
            if let key = row.duplicateKey {
                if context.existingKeys.contains(key) {
                    row.isDuplicateOfExisting = true
                    issues.append(MT5ImportIssue(.duplicateExisting, .warning, "Staat al in je journal"))
                } else if seenKeys.contains(key) {
                    issues.append(MT5ImportIssue(.duplicateInBatch, .warning, "Staat twee keer in deze import"))
                }
                seenKeys.insert(key)
            }

            row.issues = issues
            if row.hasErrors { row.isSelected = false }
            return row
        }
    }

    static func isPlausibleSymbol(_ symbol: String) -> Bool {
        let pattern = #"^[A-Z][A-Z0-9._#+\-]{2,15}$"#
        return symbol.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - P&L tegen prijsverschil en volume

    /// Prijsbeweging in de richting van de trade × volume (in punten·lots).
    static func signedMove(_ row: MT5ImportRow) -> Double? {
        guard let direction = row.direction, let volume = row.volume, let entry = row.entryPrice, let exit = row.exitPrice else { return nil }
        return (exit - entry) * direction.sign * volume
    }

    /// Verwachte waarde van 1 punt × 1 lot voor een symbool, met de
    /// toegestane afwijking (valutaomrekening naar de accountvaluta).
    static func expectedPointValue(for symbol: String, context: ValidationContext) -> Double? {
        let upper = symbol.uppercased()
        if let known = context.pointValues[upper] { return known }
        // Suffixen van brokers ("EURUSD.r", "XAUUSD#", "US30-") weglaten.
        let base = String(upper.prefix { $0.isLetter || $0.isNumber })
        if let known = context.pointValues[base] { return known }
        if base.hasPrefix("XAU") { return 100 }
        if base.hasPrefix("XAG") { return 5_000 }
        let majors: Set<String> = ["USD", "EUR", "GBP", "CHF", "CAD", "AUD", "NZD", "JPY"]
        if base.count == 6, base.allSatisfy(\.isLetter) {
            let first = String(base.prefix(3))
            let quote = String(base.suffix(3))
            guard majors.contains(first), majors.contains(quote) else { return nil }
            return quote == "JPY" ? 100_000 / 150 : 100_000
        }
        return nil
    }

    /// Mediaan van P&L / beweging per symbool over de regels zelf (minstens 3).
    static func batchPointValues(_ rows: [MT5ImportRow]) -> [String: Double] {
        var values: [String: [Double]] = [:]
        for row in rows {
            guard let move = signedMove(row), abs(move) > 0, let pnl = row.pnl, abs(pnl) >= 5 else { continue }
            values[row.symbol.uppercased(), default: []].append(pnl / move)
        }
        var result: [String: Double] = [:]
        for (symbol, list) in values where list.count >= 3 {
            let sorted = list.sorted()
            result[symbol] = sorted[sorted.count / 2]
        }
        return result
    }

    /// Melding als de P&L niet past bij prijsverschil en volume; `nil` = klopt
    /// of niet te beoordelen.
    func pnlMismatch(_ row: MT5ImportRow, context: ValidationContext, batchValues: [String: Double]) -> String? {
        guard let move = signedMove(row), let pnl = row.pnl else { return nil }

        // Richting: koers ging de goede kant op maar verlies (of andersom).
        if abs(pnl) >= 1, move != 0, (pnl > 0) != (move > 0) {
            return move > 0
                ? "P&L is negatief, maar de koers ging de kant van de trade op"
                : "P&L is positief, maar de koers ging tegen de trade in"
        }
        if move == 0 {
            return abs(pnl) >= 1 ? "P&L zonder prijsverschil" : nil
        }

        // Grootte t.o.v. het instrument (marge voor valutaomrekening).
        let implied = pnl / move
        if let expected = Self.expectedPointValue(for: row.symbol, context: context), expected > 0, abs(pnl) >= 5 {
            let ratio = implied / expected
            if ratio < 0.4 || ratio > 2.5 {
                let expectedPnL = expected * move
                return "P&L past niet bij prijsverschil en volume (verwacht ca. \(Self.format(expectedPnL)))"
            }
        }

        // Grootte t.o.v. de andere trades in dit symbool.
        if let median = batchValues[row.symbol.uppercased()] {
            let expectedPnL = median * move
            if abs(pnl - expectedPnL) > max(0.3 * abs(expectedPnL), 5) {
                return "P&L wijkt af van de andere \(row.symbol.uppercased())-trades (verwacht ca. \(Self.format(expectedPnL)))"
            }
        }
        return nil
    }

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    // MARK: - Opslaan

    /// Slaat de aangevinkte regels zonder fouten op als `Trade`, met de
    /// screenshot als bijlage en de markering "snel toegevoegd".
    ///
    /// - Entry- en sluittijd zijn beide de sluittijd (de MT5-lijst toont geen
    ///   openingstijd); de P&L van MT5 wordt het netto resultaat
    ///   (`manualNetPnL`), zoals bij de losse screenshot-import.
    /// - Geen confluences, notities of emoties: die vul je later aan.
    @discardableResult
    public func commit(
        _ rows: [MT5ImportRow],
        merged: Int,
        screenshots: [Data],
        accounts: [Account],
        playbooks: [Playbook],
        tags: [Tag],
        instruments: [Instrument],
        in context: ModelContext,
        now: Date = Date()
    ) -> MT5ImportSummary {
        var instrumentsBySymbol: [String: Instrument] = [:]
        for instrument in instruments { instrumentsBySymbol[instrument.symbol.uppercased()] = instrument }

        var summary = MT5ImportSummary(imported: 0, skippedExisting: 0, mergedOnScreenshots: merged, corrected: 0, notSelected: 0)
        for row in rows {
            guard row.isSelected, !row.hasErrors,
                  let direction = row.direction, let volume = row.volume, let entry = row.entryPrice,
                  let exit = row.exitPrice, let closeTime = row.closeTime, let pnl = row.pnl else {
                if row.isDuplicateOfExisting {
                    summary.skippedExisting += 1
                } else {
                    summary.notSelected += 1
                }
                continue
            }

            let symbol = row.symbol.trimmingCharacters(in: .whitespaces).uppercased()
            let instrument = instrumentsBySymbol[symbol]
            let account = row.accountID.flatMap { id in accounts.first { $0.id == id } }
            let spec = CSVImportService.tickSpec(
                for: ImportedTrade(symbol: symbol, direction: direction, quantity: volume, entryDate: closeTime, exitDate: closeTime,
                                   entryPrice: entry, exitPrice: exit, reportedPnL: pnl),
                instrument: instrument
            )

            let trade = Trade(
                symbol: symbol,
                direction: direction,
                entryDate: closeTime,
                exitDate: closeTime,
                entryPrice: entry,
                exitPrice: exit,
                quantity: volume,
                tickSize: spec.tickSize,
                tickValue: spec.tickValue,
                isBacktest: account?.type == .backtest,
                account: account,
                instrument: instrument,
                playbook: row.playbookID.flatMap { id in playbooks.first { $0.id == id } },
                manualNetPnL: pnl,
                createdAt: now,
                updatedAt: now
            )
            context.insert(trade)
            if let tag = row.tagID.flatMap({ id in tags.first { $0.id == id } }) {
                trade.tags = [tag]
            }
            statsService.recomputeSession(for: trade)

            if screenshots.indices.contains(row.screenshotIndex) {
                let screenshot = TradeScreenshot(imageData: screenshots[row.screenshotIndex], caption: "MT5-import", sortOrder: 0, createdAt: now)
                context.insert(screenshot)
                screenshot.trade = trade
                trade.screenshots = [screenshot]
            }

            context.insert(TradeImportMark(tradeID: trade.id, source: .mt5Screenshot, importedAt: now))

            summary.imported += 1
            if row.isEdited { summary.corrected += 1 }
        }

        do {
            try context.save()
        } catch {
            #if DEBUG
            print("MT5ScreenshotImportService.commit save error: \(error)")
            #endif
        }
        return summary
    }

    // MARK: - Markering

    /// Haalt de markering "snel toegevoegd" van een trade weg.
    public func removeMark(from trade: Trade, in context: ModelContext) {
        let tradeID = trade.id
        let marks = (try? context.fetch(FetchDescriptor<TradeImportMark>(predicate: #Predicate { $0.tradeID == tradeID }))) ?? []
        for mark in marks { context.delete(mark) }
        try? context.save()
    }

    /// Id's van alle snel toegevoegde trades.
    public static func markedTradeIDs(_ marks: [TradeImportMark]) -> Set<UUID> {
        Set(marks.map(\.tradeID))
    }
}
