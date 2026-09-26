import Foundation
import SwiftData

/// Zet een geparste CSV-tabel + kolommapping om naar trades, detecteert
/// duplicaten en schrijft de gekozen trades weg in SwiftData.
///
/// De pipeline is opgeknipt in pure stappen zodat alles zonder UI testbaar is:
/// 1. `extract` — rijen → `ImportedFill`s (samengevoegd via `FillAggregator`)
///    of direct `ImportedTrade`s, plus een lijst met probleemrijen;
/// 2. `preview` — markeert duplicaten (t.o.v. bestaande trades én binnen het
///    bestand zelf) en of het instrument bekend is;
/// 3. `commit` — maakt `Trade`s (met `TradeExecution`s voor fill-imports) aan.
public struct CSVImportService {

    /// Een rij die niet geïmporteerd kon worden, met reden.
    public struct RowIssue: Identifiable, Equatable, Sendable {
        public let row: Int
        public let message: String
        public var id: Int { row }

        public init(row: Int, message: String) {
            self.row = row
            self.message = message
        }
    }

    public struct ExtractionResult: Equatable, Sendable {
        public var trades: [ImportedTrade]
        public var issues: [RowIssue]
        /// Rijen die bewust zijn overgeslagen (bijv. geannuleerde orders).
        public var skippedRowCount: Int
    }

    /// Eén regel in het voorbeeldscherm.
    public struct PreviewItem: Identifiable, Equatable, Sendable {
        public let id: Int
        public let trade: ImportedTrade
        public let isDuplicate: Bool
        /// `false` = geen instrument-preset gevonden; P&L wordt dan afgeleid
        /// uit de gerapporteerde P&L of met puntwaarde 1 berekend.
        public let hasKnownInstrument: Bool
    }

    public let statsService: StatsService

    public init(statsService: StatsService = StatsService()) {
        self.statsService = statsService
    }

    /// Alle symbolen waar tick size/value van bekend is: de presets plus de
    /// instrumenten die de gebruiker zelf heeft aangemaakt.
    public static func knownSymbols(instruments: [Instrument]) -> Set<String> {
        var symbols = Set(InstrumentPresets.all.map { $0.symbol.uppercased() })
        for instrument in instruments where !instrument.symbol.isEmpty {
            symbols.insert(instrument.symbol.uppercased())
        }
        return symbols
    }

    // MARK: - 1. Extractie

    public func extract(from table: CSVTable, mapping: CSVColumnMapping, knownSymbols: Set<String>) -> ExtractionResult {
        // Puntkomma-gescheiden bestanden komen uit een Europese Excel-locale:
        // daar is een losse komma ("1,250") een decimaalteken.
        let parser = ImportValueParser(dateOrder: mapping.dateOrder, timeZone: mapping.timeZone, prefersDecimalComma: table.delimiter == ";")
        var issues: [RowIssue] = []
        var skipped = 0

        func text(_ field: CSVImportField, in row: [String]) -> String? {
            guard let column = mapping.columns[field], row.indices.contains(column) else { return nil }
            let trimmed = row[column].trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        func numberValue(_ field: CSVImportField, in row: [String]) -> Double? {
            text(field, in: row).flatMap(parser.number)
        }
        func dateValue(_ field: CSVImportField, in row: [String]) -> Date? {
            text(field, in: row).flatMap(parser.date)
        }
        func symbolValue(in row: [String]) -> String? {
            text(.symbol, in: row).map { ImportValueParser.normalizeSymbol($0, knownSymbols: knownSymbols) }
        }

        switch mapping.mode {
        case .fills:
            var fills: [ImportedFill] = []
            for (index, row) in table.rows.enumerated() {
                let rowNumber = index + 1

                if let status = text(.status, in: row)?.lowercased(), !status.contains("fill") {
                    skipped += 1
                    continue
                }
                guard let symbol = symbolValue(in: row) else {
                    issues.append(RowIssue(row: rowNumber, message: "Geen symbool."))
                    continue
                }
                guard let rawQuantity = numberValue(.quantity, in: row), abs(rawQuantity) > 0 else {
                    // Orders zonder gevulde hoeveelheid (bijv. geannuleerd zonder statuskolom).
                    skipped += 1
                    continue
                }
                guard let price = numberValue(.price, in: row) else {
                    issues.append(RowIssue(row: rowNumber, message: "Geen geldige prijs."))
                    continue
                }
                guard let time = dateValue(.time, in: row) else {
                    issues.append(RowIssue(row: rowNumber, message: "Geen geldige tijd."))
                    continue
                }

                let signedQuantity: Double
                if mapping.isMapped(.side) {
                    guard let side = text(.side, in: row).flatMap(parser.side) else {
                        issues.append(RowIssue(row: rowNumber, message: "Onbekende koop/verkoop-waarde."))
                        continue
                    }
                    signedQuantity = side.sign * abs(rawQuantity)
                } else {
                    signedQuantity = rawQuantity
                }

                fills.append(ImportedFill(
                    symbol: symbol,
                    date: time,
                    price: price,
                    signedQuantity: signedQuantity,
                    commission: abs(numberValue(.commission, in: row) ?? 0),
                    fees: abs(numberValue(.fees, in: row) ?? 0),
                    sourceRow: rowNumber
                ))
            }
            return ExtractionResult(trades: FillAggregator.aggregate(fills), issues: issues, skippedRowCount: skipped)

        case .trades:
            var trades: [ImportedTrade] = []
            let usesEntryExit = mapping.isMapped(.entryTime) && mapping.isMapped(.entryPrice)

            for (index, row) in table.rows.enumerated() {
                let rowNumber = index + 1
                guard let symbol = symbolValue(in: row) else {
                    issues.append(RowIssue(row: rowNumber, message: "Geen symbool."))
                    continue
                }
                let quantity = abs(numberValue(.quantity, in: row) ?? 1)
                guard quantity > 0 else {
                    skipped += 1
                    continue
                }
                let reportedPnL = numberValue(.pnl, in: row)
                let reportedNetPnL = numberValue(.netPnL, in: row)

                let direction: TradeDirection
                let entryDate: Date
                let exitDate: Date?
                let entryPrice: Double
                let exitPrice: Double?

                if usesEntryExit {
                    guard let entry = dateValue(.entryTime, in: row), let price = numberValue(.entryPrice, in: row) else {
                        issues.append(RowIssue(row: rowNumber, message: "Geen geldige entry-tijd of -prijs."))
                        continue
                    }
                    entryDate = entry
                    entryPrice = price
                    exitPrice = numberValue(.exitPrice, in: row)
                    // Zonder exit-prijs maar mét netto resultaat is de trade
                    // gesloten (snelle invoer: alleen het resultaat is bekend).
                    let isClosed = exitPrice != nil || reportedNetPnL != nil
                    exitDate = isClosed ? (dateValue(.exitTime, in: row) ?? entry) : nil

                    if let parsed = text(.direction, in: row).flatMap(parser.direction) {
                        direction = parsed
                    } else if let pnl = reportedPnL, let exit = exitPrice, exit != price {
                        // Geen richtingkolom: leid af uit P&L-teken vs. prijsbeweging.
                        direction = (pnl >= 0) == (exit > price) ? .long : .short
                    } else {
                        direction = .long
                    }
                } else {
                    guard let buyTime = dateValue(.buyTime, in: row), let sellTime = dateValue(.sellTime, in: row),
                          let buyPrice = numberValue(.buyPrice, in: row), let sellPrice = numberValue(.sellPrice, in: row) else {
                        issues.append(RowIssue(row: rowNumber, message: "Geen geldige koop-/verkooptijd of -prijs."))
                        continue
                    }
                    // Eerst gekocht = long, eerst verkocht = short.
                    direction = buyTime <= sellTime ? .long : .short
                    entryDate = direction == .long ? buyTime : sellTime
                    exitDate = direction == .long ? sellTime : buyTime
                    entryPrice = direction == .long ? buyPrice : sellPrice
                    exitPrice = direction == .long ? sellPrice : buyPrice
                }

                trades.append(ImportedTrade(
                    symbol: symbol,
                    direction: direction,
                    quantity: quantity,
                    entryDate: entryDate,
                    exitDate: exitDate,
                    entryPrice: entryPrice,
                    exitPrice: exitPrice,
                    stopLoss: numberValue(.stopLoss, in: row).flatMap { $0 == 0 ? nil : $0 },
                    takeProfit: numberValue(.takeProfit, in: row).flatMap { $0 == 0 ? nil : $0 },
                    commission: abs(numberValue(.commission, in: row) ?? 0),
                    fees: abs(numberValue(.fees, in: row) ?? 0),
                    reportedPnL: reportedPnL,
                    notes: text(.notes, in: row) ?? "",
                    sourceRows: [rowNumber],
                    reportedNetPnL: reportedNetPnL,
                    accountName: text(.account, in: row),
                    sourceID: text(.tradeID, in: row).flatMap(UUID.init(uuidString:))
                ))
            }
            trades.sort { $0.entryDate < $1.entryDate }
            return ExtractionResult(trades: trades, issues: issues, skippedRowCount: skipped)
        }
    }

    // MARK: - 2. Voorbeeld + duplicaten

    /// Markeert trades die al in het journal staan (zelfde trade-id, of zelfde
    /// symbool, richting, entry-seconde, aantal en entry-prijs) of eerder in
    /// hetzelfde bestand voorkomen als duplicaat.
    public func preview(_ trades: [ImportedTrade], existingTrades: [Trade], knownSymbols: Set<String>) -> [PreviewItem] {
        var seenIDs = Set(existingTrades.map(\.id))
        var seen = Set(existingTrades.map { trade in
            ImportedTrade.fingerprint(
                symbol: trade.symbol,
                direction: trade.direction,
                entryDate: trade.entryDate,
                quantity: trade.quantity,
                entryPrice: trade.entryPrice
            )
        })
        let known = Set(knownSymbols.map { $0.uppercased() })

        return trades.enumerated().map { index, trade in
            let fingerprint = trade.fingerprint
            let isDuplicate = seen.contains(fingerprint) || (trade.sourceID.map(seenIDs.contains) ?? false)
            seen.insert(fingerprint)
            if let sourceID = trade.sourceID { seenIDs.insert(sourceID) }
            return PreviewItem(
                id: index,
                trade: trade,
                isDuplicate: isDuplicate,
                hasKnownInstrument: known.contains(trade.symbol.uppercased())
            )
        }
    }

    // MARK: - 3. Opslaan

    /// Tick size/value voor een geïmporteerde trade. Een bekend instrument
    /// wint altijd; anders wordt de puntwaarde afgeleid uit de gerapporteerde
    /// P&L (bruto) en de prijsbeweging, met puntwaarde 1 als laatste fallback.
    public static func tickSpec(for trade: ImportedTrade, instrument: Instrument?) -> (tickSize: Double, tickValue: Double) {
        if let instrument, instrument.tickSize > 0 {
            return (instrument.tickSize, instrument.tickValue)
        }
        if let preset = InstrumentPresets.definition(for: trade.symbol) {
            return (preset.tickSize, preset.tickValue)
        }
        let fallbackTickSize = 0.01
        if let pnl = trade.reportedPnL, let exit = trade.exitPrice, trade.quantity > 0 {
            let move = abs(exit - trade.entryPrice) * trade.quantity
            if move > 0, abs(pnl) > 0 {
                let pointValue = abs(pnl) / move
                return (fallbackTickSize, pointValue * fallbackTickSize)
            }
        }
        return (fallbackTickSize, fallbackTickSize)
    }

    /// Het account voor een geïmporteerde trade: het gekozen account wint;
    /// anders een bestaand account met de naam uit het bestand.
    public static func account(for trade: ImportedTrade, selected: Account?, accounts: [Account]) -> Account? {
        if let selected { return selected }
        guard let name = trade.accountName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return accounts.first { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Slaat de geselecteerde voorbeeldregels op als `Trade`s.
    /// - Parameters:
    ///   - includeDuplicates: `false` slaat duplicaten over.
    ///   - account: gekozen account; `nil` = koppel op accountnaam uit het bestand.
    ///   - accounts: bestaande accounts om op naam te koppelen.
    /// - Returns: de aangemaakte trades.
    @discardableResult
    public func commit(
        _ items: [PreviewItem],
        includeDuplicates: Bool,
        account: Account?,
        accounts: [Account] = [],
        instruments: [Instrument],
        in context: ModelContext
    ) -> [Trade] {
        var instrumentsBySymbol: [String: Instrument] = [:]
        for instrument in instruments {
            instrumentsBySymbol[instrument.symbol.uppercased()] = instrument
        }
        // Trade-id's die al bestaan niet hergebruiken (bij "duplicaten ook importeren").
        var usedIDs = Set(((try? context.fetch(FetchDescriptor<Trade>())) ?? []).map(\.id))

        var created: [Trade] = []
        for item in items where includeDuplicates || !item.isDuplicate {
            let imported = item.trade
            let instrument = instrumentsBySymbol[imported.symbol.uppercased()]
            let spec = Self.tickSpec(for: imported, instrument: instrument)
            let hasFills = !imported.fills.isEmpty
            let account = Self.account(for: imported, selected: account, accounts: accounts)
            var id = UUID()
            if let sourceID = imported.sourceID, !usedIDs.contains(sourceID) { id = sourceID }
            usedIDs.insert(id)

            let trade = Trade(
                id: id,
                symbol: imported.symbol,
                direction: imported.direction,
                entryDate: imported.entryDate,
                exitDate: imported.exitDate,
                entryPrice: imported.entryPrice,
                exitPrice: imported.exitPrice,
                quantity: imported.quantity,
                stopLoss: imported.stopLoss,
                takeProfit: imported.takeProfit,
                // Bij fills staan de kosten per execution; niet dubbel tellen.
                commission: hasFills ? 0 : imported.commission,
                fees: hasFills ? 0 : imported.fees,
                tickSize: spec.tickSize,
                tickValue: spec.tickValue,
                notes: imported.notes,
                isBacktest: account?.type == .backtest,
                account: account,
                instrument: instrument
            )
            context.insert(trade)

            if hasFills {
                var executions: [TradeExecution] = []
                for fill in imported.fills {
                    let execution = TradeExecution(
                        date: fill.date,
                        price: fill.price,
                        signedQuantity: fill.signedQuantity,
                        commission: fill.commission,
                        fees: fill.fees
                    )
                    context.insert(execution)
                    executions.append(execution)
                }
                trade.executions = executions
            }

            // Netto resultaat uit het bestand bewaren als het niet uit de
            // prijzen volgt (snelle trade zonder prijzen, of broker-resultaat
            // dat afwijkt) — zo blijft een export → import exact gelijk.
            if !hasFills, let net = imported.reportedNetPnL {
                let computed = statsService.metrics(for: trade)
                if computed.outcome == .open || abs(computed.netPnL - net) > 0.005 {
                    trade.manualNetPnL = net
                }
            }

            statsService.recomputeSession(for: trade)
            created.append(trade)
        }

        do {
            try context.save()
        } catch {
            #if DEBUG
            print("CSVImportService.commit save error: \(error)")
            #endif
        }
        return created
    }
}
