import Foundation
import SwiftData

/// Service die het aanmaken, bijwerken, dupliceren en verwijderen van trades
/// afhandelt, inclusief de many-to-many relaties (confluences, tags, fouten)
/// en de rule-adherence van het gekoppelde playbook.
///
/// Bevat geen UI-logica: het formulier (`TradeFormViewModel`) gebruikt deze
/// service om `FormValues` weg te schrijven, zodat de mapping-logica op één
/// unit-testbare plek staat.
public struct TradeEditingService {

    public let statsService: StatsService

    public init(statsService: StatsService = StatsService()) {
        self.statsService = statsService
    }

    // MARK: - Formulierwaarden

    /// Alle bewerkbare velden van een trade als waarde-type, losstaand van
    /// SwiftData. Zo kan het tradeformulier live P&L/R voorberekenen zonder
    /// tussentijds te hoeven opslaan.
    public struct FormValues {
        public var account: Account?
        public var instrument: Instrument?
        public var symbol: String
        public var direction: TradeDirection
        public var entryDate: Date
        public var exitDate: Date?
        public var entryPrice: Double
        public var exitPrice: Double?
        public var quantity: Double
        public var stopLoss: Double?
        public var takeProfit: Double?
        public var plannedRisk: Double?
        public var mae: Double?
        public var mfe: Double?
        public var commission: Double
        public var fees: Double
        public var tickSize: Double
        public var tickValue: Double
        public var emotionBefore: String
        public var emotionAfter: String
        public var rating: Int
        public var notes: String
        public var isBacktest: Bool
        public var playbook: Playbook?
        public var confluences: [Confluence]
        public var tags: [Tag]
        public var mistakes: [Mistake]
        /// `id`'s van de regels van `playbook` die als "gevolgd" zijn aangevinkt.
        public var followedRuleIDs: Set<UUID>

        public init(
            account: Account? = nil,
            instrument: Instrument? = nil,
            symbol: String = "",
            direction: TradeDirection = .long,
            entryDate: Date = Date(),
            exitDate: Date? = nil,
            entryPrice: Double = 0,
            exitPrice: Double? = nil,
            quantity: Double = 1,
            stopLoss: Double? = nil,
            takeProfit: Double? = nil,
            plannedRisk: Double? = nil,
            mae: Double? = nil,
            mfe: Double? = nil,
            commission: Double = 0,
            fees: Double = 0,
            tickSize: Double = 0.01,
            tickValue: Double = 1,
            emotionBefore: String = "",
            emotionAfter: String = "",
            rating: Int = 0,
            notes: String = "",
            isBacktest: Bool = false,
            playbook: Playbook? = nil,
            confluences: [Confluence] = [],
            tags: [Tag] = [],
            mistakes: [Mistake] = [],
            followedRuleIDs: Set<UUID> = []
        ) {
            self.account = account
            self.instrument = instrument
            self.symbol = symbol
            self.direction = direction
            self.entryDate = entryDate
            self.exitDate = exitDate
            self.entryPrice = entryPrice
            self.exitPrice = exitPrice
            self.quantity = quantity
            self.stopLoss = stopLoss
            self.takeProfit = takeProfit
            self.plannedRisk = plannedRisk
            self.mae = mae
            self.mfe = mfe
            self.commission = commission
            self.fees = fees
            self.tickSize = tickSize
            self.tickValue = tickValue
            self.emotionBefore = emotionBefore
            self.emotionAfter = emotionAfter
            self.rating = rating
            self.notes = notes
            self.isBacktest = isBacktest
            self.playbook = playbook
            self.confluences = confluences
            self.tags = tags
            self.mistakes = mistakes
            self.followedRuleIDs = followedRuleIDs
        }

        /// Standaardwaarden voor een nieuwe trade: neemt account, instrument,
        /// symbool, richting, aantal, kosten en playbook over van de laatst
        /// aangemaakte trade zodat snel-invoeren zo min mogelijk getik kost.
        /// Resultaat-specifieke velden (prijzen, exit, notities) beginnen leeg.
        public static func makeDefault(basedOn lastTrade: Trade?, fallbackAccount: Account?) -> FormValues {
            guard let last = lastTrade else {
                return FormValues(account: fallbackAccount, entryDate: Date())
            }
            return FormValues(
                account: last.account ?? fallbackAccount,
                instrument: last.instrument,
                symbol: last.symbol,
                direction: last.direction,
                entryDate: Date(),
                exitDate: nil,
                entryPrice: 0,
                exitPrice: nil,
                quantity: last.quantity,
                stopLoss: nil,
                takeProfit: nil,
                plannedRisk: last.plannedRisk,
                commission: last.commission,
                fees: last.fees,
                tickSize: last.tickSize,
                tickValue: last.tickValue,
                isBacktest: last.isBacktest,
                playbook: last.playbook
            )
        }
    }

    // MARK: - Lezen

    /// Zet een bestaande `Trade` om naar bewerkbare `FormValues`.
    public func values(from trade: Trade) -> FormValues {
        FormValues(
            account: trade.account,
            instrument: trade.instrument,
            symbol: trade.symbol,
            direction: trade.direction,
            entryDate: trade.entryDate,
            exitDate: trade.exitDate,
            entryPrice: trade.entryPrice,
            exitPrice: trade.exitPrice,
            quantity: trade.quantity,
            stopLoss: trade.stopLoss,
            takeProfit: trade.takeProfit,
            plannedRisk: trade.plannedRisk,
            mae: trade.mae,
            mfe: trade.mfe,
            commission: trade.commission,
            fees: trade.fees,
            tickSize: trade.tickSize,
            tickValue: trade.tickValue,
            emotionBefore: trade.emotionBefore,
            emotionAfter: trade.emotionAfter,
            rating: trade.rating,
            notes: trade.notes,
            isBacktest: trade.isBacktest,
            playbook: trade.playbook,
            confluences: trade.confluences,
            tags: trade.tags,
            mistakes: trade.mistakes,
            followedRuleIDs: Set(trade.ruleAdherence.filter(\.followed).compactMap { $0.rule?.id })
        )
    }

    // MARK: - Schrijven

    /// Maakt een nieuwe trade op basis van `values`, voegt hem toe aan `context`
    /// en geeft hem terug.
    @discardableResult
    public func createTrade(from values: FormValues, in context: ModelContext) -> Trade {
        let trade = Trade(
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
            mae: values.mae,
            mfe: values.mfe,
            commission: values.commission,
            fees: values.fees,
            tickSize: values.tickSize,
            tickValue: values.tickValue,
            emotionBefore: values.emotionBefore,
            emotionAfter: values.emotionAfter,
            rating: values.rating,
            notes: values.notes,
            isBacktest: values.isBacktest,
            account: values.account,
            instrument: values.instrument,
            playbook: values.playbook
        )
        context.insert(trade)
        apply(relationships: values, to: trade, in: context)
        statsService.recomputeSession(for: trade)
        return trade
    }

    /// Werkt een bestaande trade bij met `values`.
    public func update(_ trade: Trade, with values: FormValues, in context: ModelContext) {
        trade.symbol = values.symbol
        trade.direction = values.direction
        trade.entryDate = values.entryDate
        trade.exitDate = values.exitDate
        trade.entryPrice = values.entryPrice
        trade.exitPrice = values.exitPrice
        trade.quantity = values.quantity
        trade.stopLoss = values.stopLoss
        trade.takeProfit = values.takeProfit
        trade.plannedRisk = values.plannedRisk
        trade.mae = values.mae
        trade.mfe = values.mfe
        trade.commission = values.commission
        trade.fees = values.fees
        trade.tickSize = values.tickSize
        trade.tickValue = values.tickValue
        trade.emotionBefore = values.emotionBefore
        trade.emotionAfter = values.emotionAfter
        trade.rating = values.rating
        trade.notes = values.notes
        trade.isBacktest = values.isBacktest
        trade.account = values.account
        trade.instrument = values.instrument
        trade.playbook = values.playbook

        apply(relationships: values, to: trade, in: context)
        statsService.recomputeSession(for: trade)
        trade.updatedAt = Date()
    }

    /// Past confluences/tags/fouten en de rule-adherence van het gekozen
    /// playbook toe. Bestaande `PlaybookRuleAdherence`-rijen worden altijd
    /// vervangen door een verse set, zodat regels van een ander (of geen)
    /// playbook niet blijven hangen.
    private func apply(relationships values: FormValues, to trade: Trade, in context: ModelContext) {
        trade.confluences = values.confluences
        trade.tags = values.tags
        trade.mistakes = values.mistakes

        for adherence in trade.ruleAdherence {
            context.delete(adherence)
        }
        trade.ruleAdherence = []

        guard let playbook = values.playbook else { return }
        for rule in playbook.rules {
            let adherence = PlaybookRuleAdherence(followed: values.followedRuleIDs.contains(rule.id))
            adherence.rule = rule
            adherence.trade = trade
            context.insert(adherence)
            trade.ruleAdherence.append(adherence)
        }
    }

    // MARK: - Dupliceren & verwijderen

    /// Maakt een kopie van `trade` als startpunt voor een nieuwe, vergelijkbare
    /// trade: account/instrument/playbook/confluences/tags blijven staan, de
    /// entry-tijd wordt "nu", en resultaat-specifieke velden (exit, notities,
    /// emoties, rating, fouten, screenshots, executions) beginnen leeg.
    @discardableResult
    public func duplicate(_ trade: Trade, in context: ModelContext) -> Trade {
        let copy = Trade(
            symbol: trade.symbol,
            direction: trade.direction,
            entryDate: Date(),
            exitDate: nil,
            entryPrice: trade.entryPrice,
            exitPrice: nil,
            quantity: trade.quantity,
            stopLoss: trade.stopLoss,
            takeProfit: trade.takeProfit,
            plannedRisk: trade.plannedRisk,
            commission: trade.commission,
            fees: trade.fees,
            tickSize: trade.tickSize,
            tickValue: trade.tickValue,
            isBacktest: trade.isBacktest,
            account: trade.account,
            instrument: trade.instrument,
            playbook: trade.playbook
        )
        context.insert(copy)
        copy.confluences = trade.confluences
        copy.tags = trade.tags
        statsService.recomputeSession(for: copy)
        return copy
    }

    /// Verwijdert een trade. Executions, screenshots en rule-adherence gaan
    /// mee via hun cascade-`deleteRule`.
    public func delete(_ trade: Trade, from context: ModelContext) {
        context.delete(trade)
    }

    // MARK: - Screenshots

    @discardableResult
    public func addScreenshot(_ imageData: Data, caption: String = "", to trade: Trade, in context: ModelContext) -> TradeScreenshot {
        let nextOrder = (trade.screenshots.map(\.sortOrder).max() ?? -1) + 1
        let screenshot = TradeScreenshot(imageData: imageData, caption: caption, sortOrder: nextOrder)
        screenshot.trade = trade
        context.insert(screenshot)
        trade.screenshots.append(screenshot)
        return screenshot
    }

    public func removeScreenshot(_ screenshot: TradeScreenshot, from trade: Trade, in context: ModelContext) {
        trade.screenshots.removeAll { $0.id == screenshot.id }
        context.delete(screenshot)
    }
}
