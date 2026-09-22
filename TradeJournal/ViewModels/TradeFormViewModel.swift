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

    public let mode: Mode
    private let editingService: TradeEditingService
    private let statsService: StatsService

    public init(
        mode: Mode,
        lastTrade: Trade? = nil,
        fallbackAccount: Account? = nil,
        editingService: TradeEditingService = TradeEditingService(),
        statsService: StatsService = StatsService()
    ) {
        self.mode = mode
        self.editingService = editingService
        self.statsService = statsService
        switch mode {
        case .create:
            self.values = .makeDefault(basedOn: lastTrade, fallbackAccount: fallbackAccount)
        case .edit(let trade):
            self.values = editingService.values(from: trade)
        }
    }

    public var title: String { mode.isEditing ? "Trade bewerken" : "Nieuwe trade" }

    public var isValid: Bool {
        !values.symbol.trimmingCharacters(in: .whitespaces).isEmpty
            && values.quantity > 0
            && values.tickSize > 0
            && values.entryPrice != 0
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
            tickValue: values.tickValue
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

    /// Slaat het formulier op: maakt een nieuwe trade aan of werkt de
    /// bestaande bij, en voegt eventuele nieuwe screenshots toe.
    @discardableResult
    public func save(in context: ModelContext) -> Trade {
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
