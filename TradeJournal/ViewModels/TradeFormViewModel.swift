import Foundation
import SwiftData

/// Viewmodel achter `TradeFormView` — zowel voor het aanmaken van een nieuwe
/// trade als het bewerken van een bestaande.
///
/// Rekent P&L/R live voor op basis van de huidige formulierwaarden (zonder
/// tussentijds op te slaan) door `StatsService` tegen een niet-ingevoegde
/// `Trade` te draaien — zo blijft er precies één plek met P&L-logica.
@Observable
public final class TradeFormViewModel {

    /// Uitgebreid (alle velden, P&L uit prijzen) of snel (alleen resultaat,
    /// symbool en confluences).
    public enum EntryStyle: String, CaseIterable, Identifiable {
        case detailed
        case quick

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .detailed: return "Uitgebreid"
            case .quick: return "Snel"
            }
        }
    }

    public enum Mode {
        case create
        case edit(Trade)

        public var isEditing: Bool {
            if case .edit = self { return true }
            return false
        }
    }

    public var values: TradeEditingService.FormValues

    /// Screenshots die tijdens deze formuliersessie zijn toegevoegd maar nog
    /// niet opgeslagen zijn. Worden bij `save(in:)` als `TradeScreenshot`
    /// aangemaakt.
    public var pendingScreenshots: [Data] = []

    /// Standaard uitgebreid; een bestaande snelle trade opent in "Snel".
    public var entryStyle: EntryStyle = .detailed

    /// Snelle invoer: winst (`true`) of verlies, en het bedrag (≥ 0).
    public var quickIsProfit: Bool = true
    public var quickAmount: Double = 0

    /// Uitgebreid: netto resultaat zoals de broker het toont (bijv. van de
    /// screenshot, in de valuta van het account). Gezet → gaat vóór de
    /// berekening uit prijzen × tick value (`Trade.manualNetPnL`); `nil` →
    /// P&L uit de prijzen.
    public var brokerNetPnL: Double?

    // MARK: Screenshot-import (OCR)

    /// Hoe een veld door de screenshot-import is ingevuld.
    public enum OCRFieldOrigin: Equatable {
        /// Letterlijk van de screenshot gelezen.
        case recognized
        /// Berekend uit andere gelezen waarden (bijv. exit uit P&L).
        case derived
    }

    /// Eén keuze in de chip-rij met alternatieven van een veld.
    public struct OCRCandidate: Identifiable, Equatable {
        public let id: Int
        public let label: String
        public let isSelected: Bool
    }

    /// Velden die de screenshot-import heeft ingevuld (voor het "uit OCR"-icoon).
    public private(set) var ocrOrigins: [ScreenshotField: OCRFieldOrigin] = [:]
    /// Laatste parse-resultaat (bron van de alternatieven).
    public private(set) var ocrResult: ScreenshotParseResult?
    /// Melding na een import (succes, niets gevonden of fout).
    public var ocrMessage: String?
    public private(set) var isRecognizingScreenshot = false

    public let mode: Mode
    private let editingService: TradeEditingService
    private let statsService: StatsService
    private let textRecognizer: any ScreenshotTextRecognizing
    private let screenshotTemplates: [ScreenshotTemplate]
    /// Instrumenten van de laatste import, voor het wisselen van symbool-kandidaat.
    private var ocrInstruments: [Instrument] = []

    public init(
        mode: Mode,
        lastTrade: Trade? = nil,
        fallbackAccount: Account? = nil,
        initialDate: Date? = nil,
        editingService: TradeEditingService = TradeEditingService(),
        statsService: StatsService = StatsService(),
        textRecognizer: any ScreenshotTextRecognizing = VisionTextRecognizer(),
        screenshotTemplates: [ScreenshotTemplate] = ScreenshotTemplateStore.bundled
    ) {
        self.mode = mode
        self.editingService = editingService
        self.statsService = statsService
        self.textRecognizer = textRecognizer
        self.screenshotTemplates = screenshotTemplates
        switch mode {
        case .create:
            self.values = .makeDefault(basedOn: lastTrade, fallbackAccount: fallbackAccount)
            if let initialDate {
                values.entryDate = Self.combine(day: initialDate, timeOfDay: values.entryDate)
            }
        case .edit(let trade):
            self.values = editingService.values(from: trade)
            if let manual = trade.manualNetPnL {
                if trade.entryPrice == 0, (trade.exitPrice ?? 0) == 0 {
                    entryStyle = .quick
                    quickIsProfit = manual >= 0
                    quickAmount = abs(manual)
                } else {
                    // Uitgebreide trade met het resultaat van de broker.
                    brokerNetPnL = manual
                }
            }
        }
    }

    /// Combineert de kalenderdag van `day` met het uur/minuut van `timeOfDay`,
    /// zodat "snel een trade toevoegen" vanuit de dagdetail start op de
    /// gekozen dag in plaats van vandaag.
    private static func combine(day: Date, timeOfDay: Date) -> Date {
        let calendar = Calendar.current
        var merged = calendar.dateComponents([.year, .month, .day], from: day)
        let time = calendar.dateComponents([.hour, .minute, .second], from: timeOfDay)
        merged.hour = time.hour
        merged.minute = time.minute
        merged.second = time.second
        return calendar.date(from: merged) ?? day
    }

    public var title: String { mode.isEditing ? "Trade bewerken" : "Nieuwe trade" }

    public var isValid: Bool { missingFields.isEmpty }

    /// Wat er nog ontbreekt om te kunnen opslaan — getoond in het formulier,
    /// zodat een uitgeschakelde "Opslaan"-knop niet raadselachtig is.
    ///
    /// Alleen het symbool is echt verplicht: een trade mag ook zonder prijzen
    /// (snel iets vastleggen). Wel: een exit-prijs zonder entry-prijs zou een
    /// absurde P&L opleveren, dus dan is de entry-prijs verplicht.
    public var missingFields: [String] {
        var missing: [String] = []
        if values.symbol.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("Symbool (of kies een preset)") }
        // Snel: alleen het symbool; een bedrag van 0 is breakeven.
        guard entryStyle == .detailed else { return missing }
        if values.entryPrice == 0, let exit = values.exitPrice, exit != 0 {
            missing.append("Entry-prijs (nodig als je een exit-prijs invult)")
        }
        if values.quantity <= 0 { missing.append("Aantal contracten/lots groter dan 0") }
        if values.tickSize <= 0 { missing.append("Tick size groter dan 0") }
        return missing
    }

    /// Trade zonder prijzen: wordt opgeslagen maar telt niet mee in P&L en
    /// win rate (geen exit-prijs → geen resultaat).
    public var hasNoPrices: Bool {
        entryStyle == .detailed && values.entryPrice == 0 && (values.exitPrice ?? 0) == 0
    }

    /// Netto resultaat zoals de snelle invoer het opslaat.
    public var quickNetPnL: Double {
        quickIsProfit ? abs(quickAmount) : -abs(quickAmount)
    }

    /// Zet `manualNetPnL` volgens de gekozen stijl. Snel: resultaat handmatig
    /// en de trade telt als gesloten; uitgebreid: het resultaat van de broker
    /// als dat is ingevuld, anders P&L uit de prijzen.
    private func applyEntryStyle() {
        switch entryStyle {
        case .quick:
            values.manualNetPnL = quickNetPnL
            if values.exitDate == nil { values.exitDate = values.entryDate }
        case .detailed:
            values.manualNetPnL = brokerNetPnL
        }
    }

    /// Screenshots die al bij de trade horen (alleen relevant bij bewerken).
    public var existingScreenshots: [TradeScreenshot] {
        guard case .edit(let trade) = mode else { return [] }
        return trade.screenshots.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Live-berekende P&L/R op basis van de huidige waarden, zonder op te slaan.
    public var livePreview: TradeMetrics {
        let transient = Trade(
            symbol: values.symbol,
            direction: values.direction,
            entryDate: values.entryDate,
            exitDate: values.exitDate,
            entryPrice: values.entryPrice,
            exitPrice: values.exitPrice,
            quantity: values.quantity,
            stopLoss: values.stopLoss,
            takeProfit: values.takeProfit,
            plannedRisk: values.plannedRisk,
            commission: values.commission,
            fees: values.fees,
            tickSize: values.tickSize,
            tickValue: values.tickValue,
            manualNetPnL: entryStyle == .quick ? quickNetPnL : brokerNetPnL
        )
        return statsService.metrics(for: transient)
    }

    /// Sessie die automatisch bepaald wordt uit `entryDate`.
    public var detectedSession: Session {
        statsService.sessionCalculator.session(for: values.entryDate)
    }

    // MARK: - Acties

    public func applyInstrumentPreset(_ instrument: Instrument) {
        values.instrument = instrument
        if values.symbol.trimmingCharacters(in: .whitespaces).isEmpty {
            values.symbol = instrument.symbol
        }
        values.tickSize = instrument.tickSize
        values.tickValue = instrument.tickValue
        if values.quantity <= 0 {
            values.quantity = instrument.defaultQuantity
        }
    }

    public func applyPlaybook(_ playbook: Playbook?) {
        values.playbook = playbook
        // Regels van een ander (of geen) playbook zijn niet meer relevant.
        values.followedRuleIDs = []
    }

    public func toggle(_ confluence: Confluence) {
        if let idx = values.confluences.firstIndex(where: { $0.id == confluence.id }) {
            values.confluences.remove(at: idx)
        } else {
            values.confluences.append(confluence)
        }
    }

    public func isSelected(_ confluence: Confluence) -> Bool {
        values.confluences.contains { $0.id == confluence.id }
    }

    public func toggle(_ tag: Tag) {
        if let idx = values.tags.firstIndex(where: { $0.id == tag.id }) {
            values.tags.remove(at: idx)
        } else {
            values.tags.append(tag)
        }
    }

    public func isSelected(_ tag: Tag) -> Bool {
        values.tags.contains { $0.id == tag.id }
    }

    public func toggle(_ mistake: Mistake) {
        if let idx = values.mistakes.firstIndex(where: { $0.id == mistake.id }) {
            values.mistakes.remove(at: idx)
        } else {
            values.mistakes.append(mistake)
        }
    }

    public func isSelected(_ mistake: Mistake) -> Bool {
        values.mistakes.contains { $0.id == mistake.id }
    }

    public func setRule(_ rule: PlaybookRule, followed: Bool) {
        if followed {
            values.followedRuleIDs.insert(rule.id)
        } else {
            values.followedRuleIDs.remove(rule.id)
        }
    }

    public func isRuleFollowed(_ rule: PlaybookRule) -> Bool {
        values.followedRuleIDs.contains(rule.id)
    }

    public func addPendingScreenshot(_ data: Data) {
        pendingScreenshots.append(data)
    }

    public func removePendingScreenshot(at index: Int) {
        guard pendingScreenshots.indices.contains(index) else { return }
        pendingScreenshots.remove(at: index)
    }

    public func removeExistingScreenshot(_ screenshot: TradeScreenshot, in context: ModelContext) {
        guard case .edit(let trade) = mode else { return }
        editingService.removeScreenshot(screenshot, from: trade, in: context)
    }

    // MARK: - Screenshot-import (OCR)

    /// "Vul in vanuit screenshot": koppelt de screenshot als bijlage, leest de
    /// tekst on-device (Vision) en vult de herkende velden in. Faalt de OCR of
    /// wordt niets herkend, dan blijft het formulier zoals het was (met de
    /// screenshot al bijgevoegd) en staat er een melding in `ocrMessage`.
    @MainActor
    public func importScreenshot(_ data: Data, instruments: [Instrument]) async {
        addPendingScreenshot(data)
        isRecognizingScreenshot = true
        defer { isRecognizingScreenshot = false }
        do {
            let lines = try await textRecognizer.recognizeLines(in: data)
            let parser = ScreenshotParser(
                templates: screenshotTemplates,
                knownSymbols: CSVImportService.knownSymbols(instruments: instruments)
            )
            applyScreenshotResult(parser.parse(lines: lines, referenceDate: values.entryDate), instruments: instruments)
        } catch {
            ocrResult = nil
            ocrOrigins = [:]
            ocrMessage = "De tekst op de screenshot kon niet gelezen worden. De screenshot is wel als bijlage toegevoegd; vul de trade handmatig in."
        }
    }

    /// Vult het formulier met een parse-resultaat. Alleen gevonden velden
    /// worden overschreven; ontbrekende exit-prijs of aantal worden, als de
    /// tick-specificatie van het instrument bekend is, uit de P&L berekend.
    public func applyScreenshotResult(_ result: ScreenshotParseResult, instruments: [Instrument]) {
        ocrResult = result
        ocrInstruments = instruments
        ocrOrigins = [:]
        guard !result.isEmpty else {
            ocrMessage = "Geen tradegegevens herkend op de screenshot. De screenshot is als bijlage toegevoegd; vul de velden handmatig in."
            return
        }

        if let symbol = result.symbol {
            applyOCRSymbol(symbol.value, instruments: instruments)
            markOCR(.symbol, symbol)
        }
        if let direction = result.direction {
            values.direction = direction.value
            markOCR(.direction, direction)
        }
        if let quantity = result.quantity {
            values.quantity = quantity.value
            markOCR(.quantity, quantity)
        }
        if let entry = result.entryPrice {
            values.entryPrice = entry.value
            markOCR(.entryPrice, entry)
        }
        if let stop = result.stopLoss {
            values.stopLoss = stop.value
            markOCR(.stopLoss, stop)
        }
        if let target = result.takeProfit {
            values.takeProfit = target.value
            markOCR(.takeProfit, target)
        }
        if let commission = result.commission {
            values.commission = commission.value
            markOCR(.commission, commission)
        }
        if let fees = result.fees {
            values.fees = fees.value
            markOCR(.fees, fees)
        }
        if let entryTime = result.entryTime {
            values.entryDate = entryTime.value
            markOCR(.entryTime, entryTime)
        }
        if let exit = result.exitPrice {
            values.exitPrice = exit.value
            markOCR(.exitPrice, exit)
        }
        if let exitTime = result.exitTime {
            values.exitDate = max(exitTime.value, values.entryDate)
            markOCR(.exitTime, exitTime)
        } else if result.exitPrice != nil, values.exitDate == nil {
            // Exit-prijs zonder tijd: gesloten trade op het entry-moment.
            values.exitDate = values.entryDate
        }

        // Bruto én netto zichtbaar maar geen kosten: het verschil is de commissie.
        if result.commission == nil, result.fees == nil,
           let gross = result.grossPnL?.value, let net = result.netPnL?.value, gross - net > StatsService.breakevenTolerance {
            values.commission = StatsService.rounded(gross - net, toPrecisionOf: 0.01)
            ocrOrigins[.commission] = .derived
        }

        deriveMissingOCRValues(from: result)
        applyOCREntryStyle(from: result)

        let count = ocrOrigins.count
        let fieldsText = count == 1 ? "1 veld" : "\(count) velden"
        if let name = result.templateName {
            ocrMessage = "Herkend als \(name): \(fieldsText) ingevuld. Controleer de gemarkeerde velden."
        } else {
            ocrMessage = "Geen bekend platform herkend; met generieke herkenning \(fieldsText) ingevuld. Controleer de gemarkeerde velden."
        }
    }

    /// Bruto P&L zoals de screenshot hem toont, of netto + kosten.
    private func ocrGrossPnL(from result: ScreenshotParseResult) -> Double? {
        if let gross = result.grossPnL?.value { return gross }
        if let net = result.netPnL?.value { return net + values.commission + values.fees }
        return nil
    }

    /// Ontbrekend aantal of exit-prijs uitrekenen met tick size/value van het
    /// instrument (alleen als die bekend is: preset of eigen instrument).
    private func deriveMissingOCRValues(from result: ScreenshotParseResult) {
        let hasTickSpec = values.instrument != nil || InstrumentPresets.definition(for: values.symbol) != nil
        guard hasTickSpec, let gross = ocrGrossPnL(from: result) else { return }

        if result.quantity == nil, let entry = result.entryPrice?.value, let exit = result.exitPrice?.value,
           let quantity = statsService.quantity(
               forGrossPnL: gross, entryPrice: entry, exitPrice: exit,
               direction: values.direction, tickSize: values.tickSize, tickValue: values.tickValue
           ) {
            values.quantity = quantity
            ocrOrigins[.quantity] = .derived
        }

        if result.exitPrice == nil, result.entryPrice != nil,
           let exit = statsService.exitPrice(
               forGrossPnL: gross, entryPrice: values.entryPrice, quantity: values.quantity,
               direction: values.direction, tickSize: values.tickSize, tickValue: values.tickValue
           ) {
            values.exitPrice = exit
            ocrOrigins[.exitPrice] = .derived
            if values.exitDate == nil { values.exitDate = values.entryDate }
        }
    }

    /// Netto P&L van de screenshot: netto zoals getoond, of bruto min de
    /// gelezen kosten (met de bruto-alternatieven als netto-alternatieven).
    private static func screenshotNetPnL(from result: ScreenshotParseResult) -> ParsedField<Double>? {
        if let net = result.netPnL { return net }
        guard let gross = result.grossPnL else { return nil }
        let costs = (result.commission?.value ?? 0) + (result.fees?.value ?? 0)
        let toNet = { (value: Double) in StatsService.rounded(value - costs, toPrecisionOf: 0.01) }
        return ParsedField(
            value: toNet(gross.value),
            alternatives: gross.alternatives.map(toNet),
            source: gross.source,
            isDerived: true
        )
    }

    /// Met prijzen: uitgebreide invoer; een P&L op de screenshot wordt het
    /// resultaat van de broker (gaat vóór de berekening, die bij een andere
    /// accountvaluta of onbekende tick value afwijkt). Alleen een resultaat
    /// (geen prijzen): snelle invoer met dat bedrag.
    private func applyOCREntryStyle(from result: ScreenshotParseResult) {
        let net = Self.screenshotNetPnL(from: result)?.value
        if values.entryPrice > 0 || result.exitPrice != nil {
            entryStyle = .detailed
            if let net {
                brokerNetPnL = net
                ocrOrigins[.netPnL] = result.netPnL != nil ? .recognized : .derived
            }
            return
        }
        guard let net else { return }
        entryStyle = .quick
        quickIsProfit = net >= 0
        quickAmount = abs(net)
        ocrOrigins[.netPnL] = result.netPnL != nil ? .recognized : .derived
    }

    private func markOCR<T: Equatable>(_ field: ScreenshotField, _ parsed: ParsedField<T>) {
        ocrOrigins[field] = parsed.isDerived ? .derived : .recognized
    }

    /// Zet het symbool en zoekt het instrument: eerst in de eigen tabel, dan
    /// in de presets (voor tick size/value).
    private func applyOCRSymbol(_ symbol: String, instruments: [Instrument]) {
        let key = symbol.uppercased()
        values.symbol = key
        if let instrument = instruments.first(where: { $0.symbol.uppercased() == key }) {
            values.instrument = instrument
            values.tickSize = instrument.tickSize
            values.tickValue = instrument.tickValue
        } else {
            values.instrument = nil
            if let preset = InstrumentPresets.definition(for: key) {
                values.tickSize = preset.tickSize
                values.tickValue = preset.tickValue
            }
        }
    }

    /// Hoe het veld is ingevuld door de import, of `nil` als het niet uit OCR komt.
    public func ocrOrigin(for field: ScreenshotField) -> OCRFieldOrigin? {
        ocrOrigins[field]
    }

    /// Alternatieven voor een veld als chip-rij; leeg als er maar één kandidaat is.
    public func ocrCandidates(for field: ScreenshotField) -> [OCRCandidate] {
        guard let result = ocrResult, ocrOrigins[field] != nil else { return [] }
        switch field {
        case .symbol:
            return Self.candidates(result.symbol, current: values.symbol) { $0 }
        case .direction:
            return Self.candidates(result.direction, current: values.direction) { $0.displayName }
        case .entryPrice:
            return Self.candidates(result.entryPrice, current: values.entryPrice, label: Self.numberLabel)
        case .exitPrice:
            return Self.candidates(result.exitPrice, current: values.exitPrice, label: Self.numberLabel)
        case .stopLoss:
            return Self.candidates(result.stopLoss, current: values.stopLoss, label: Self.numberLabel)
        case .takeProfit:
            return Self.candidates(result.takeProfit, current: values.takeProfit, label: Self.numberLabel)
        case .quantity:
            return Self.candidates(result.quantity, current: values.quantity, label: Self.numberLabel)
        case .commission:
            return Self.candidates(result.commission, current: values.commission, label: Self.numberLabel)
        case .fees:
            return Self.candidates(result.fees, current: values.fees, label: Self.numberLabel)
        case .netPnL:
            return Self.candidates(Self.screenshotNetPnL(from: result), current: entryStyle == .quick ? quickNetPnL : brokerNetPnL, label: Self.numberLabel)
        case .entryTime:
            return Self.candidates(result.entryTime, current: values.entryDate, label: Self.dateLabel)
        case .exitTime:
            return Self.candidates(result.exitTime, current: values.exitDate, label: Self.dateLabel)
        case .grossPnL, .buyPrice, .sellPrice, .buyTime, .sellTime:
            return []
        }
    }

    /// Kiest een alternatief uit de chip-rij van `field`.
    public func selectOCRCandidate(_ index: Int, for field: ScreenshotField) {
        guard let result = ocrResult else { return }
        func pick<T: Equatable>(_ parsed: ParsedField<T>?) -> T? {
            guard let candidates = parsed?.candidates, candidates.indices.contains(index) else { return nil }
            return candidates[index]
        }
        switch field {
        case .symbol:
            guard let symbol = pick(result.symbol) else { return }
            applyOCRSymbol(symbol, instruments: ocrInstruments)
        case .direction:
            guard let direction = pick(result.direction) else { return }
            values.direction = direction
        case .entryPrice:
            guard let price = pick(result.entryPrice) else { return }
            values.entryPrice = price
        case .exitPrice:
            guard let price = pick(result.exitPrice) else { return }
            values.exitPrice = price
            if values.exitDate == nil { values.exitDate = values.entryDate }
        case .stopLoss:
            guard let price = pick(result.stopLoss) else { return }
            values.stopLoss = price
        case .takeProfit:
            guard let price = pick(result.takeProfit) else { return }
            values.takeProfit = price
        case .quantity:
            guard let quantity = pick(result.quantity) else { return }
            values.quantity = quantity
        case .commission:
            guard let commission = pick(result.commission) else { return }
            values.commission = commission
        case .fees:
            guard let fees = pick(result.fees) else { return }
            values.fees = fees
        case .netPnL:
            guard let net = pick(Self.screenshotNetPnL(from: result)) else { return }
            if entryStyle == .quick {
                quickIsProfit = net >= 0
                quickAmount = abs(net)
            } else {
                brokerNetPnL = net
            }
        case .entryTime:
            guard let date = pick(result.entryTime) else { return }
            values.entryDate = date
        case .exitTime:
            guard let date = pick(result.exitTime) else { return }
            values.exitDate = max(date, values.entryDate)
        case .grossPnL, .buyPrice, .sellPrice, .buyTime, .sellTime:
            return
        }
        ocrOrigins[field] = .recognized
    }

    /// Bruto/netto P&L zoals op de screenshot, om naast de berekende P&L te controleren.
    public var ocrScreenshotPnLText: String? {
        guard let result = ocrResult else { return nil }
        let currency = values.account?.currency ?? "USD"
        if let net = result.netPnL?.value {
            return "Netto P&L op screenshot: \(net.formatted(.currency(code: currency)))"
        }
        if let gross = result.grossPnL?.value {
            return "Bruto P&L op screenshot: \(gross.formatted(.currency(code: currency)))"
        }
        return nil
    }

    private static func candidates<T: Equatable>(_ parsed: ParsedField<T>?, current: T?, label: (T) -> String) -> [OCRCandidate] {
        guard let parsed, parsed.candidates.count > 1 else { return [] }
        return parsed.candidates.enumerated().map { index, value in
            OCRCandidate(id: index, label: label(value), isSelected: value == current)
        }
    }

    private static func numberLabel(_ value: Double) -> String {
        value == 0 ? "0" : DecimalInput.format(value)
    }

    private static func dateLabel(_ value: Date) -> String {
        value.formatted(date: .abbreviated, time: .standard)
    }

    /// Slaat het formulier op: maakt een nieuwe trade aan of werkt de
    /// bestaande bij, en voegt eventuele nieuwe screenshots toe.
    @discardableResult
    public func save(in context: ModelContext) -> Trade {
        // Zonder prijzen geen exit-prijs van 0 opslaan: dat zou als breakeven
        // meetellen in de win rate. Zonder exit-prijs telt de trade niet mee.
        if hasNoPrices { values.exitPrice = nil }
        applyEntryStyle()

        let trade: Trade
        switch mode {
        case .create:
            trade = editingService.createTrade(from: values, in: context)
        case .edit(let existing):
            editingService.update(existing, with: values, in: context)
            trade = existing
        }

        for data in pendingScreenshots {
            editingService.addScreenshot(data, to: trade, in: context)
        }
        pendingScreenshots = []

        return trade
    }
}
