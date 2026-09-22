import Foundation
import SwiftData

/// Één trade in het journal.
///
/// Bevat alle velden uit SPEC.md §3: instrument, richting, tijden, prijzen, aantal,
/// stop/target, fees, geplande risk, MAE/MFE, sessie (automatisch afgeleid), playbook,
/// confluences (many-to-many), tags, mistakes, emoties, rating, notities, screenshots,
/// executions (partial exits) en regel-adherence per playbook-regel.
///
/// Alle P&L- en R-multiple-berekeningen worden **niet** hier gecached maar door
/// `StatsService`/`Trade.metrics(...)` on-demand berekend. Zo blijven de cijfers
/// consistent als tick-instellingen of executions later worden bijgewerkt.
@Model
public final class Trade {

    // MARK: - Identiteit

    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    // MARK: - Instrument & richting

    /// Symbool zoals door de gebruiker ingevoerd (bijv. "NQ", "EURUSD"). Vrij tekstveld
    /// zodat trades zichzelf kunnen beschrijven ook als de bijbehorende `Instrument`
    /// later verwijderd wordt.
    public var symbol: String = ""

    /// Ruwe waarde van `TradeDirection`.
    public var directionRaw: String = TradeDirection.long.rawValue

    // MARK: - Tijden & prijzen

    /// Tijdstip van (eerste) entry.
    public var entryDate: Date = Date()

    /// Tijdstip van (laatste) exit. `nil` betekent nog open.
    public var exitDate: Date? = nil

    /// Entry-prijs. Bij meerdere executions is dit de gemiddelde entry.
    public var entryPrice: Double = 0

    /// Exit-prijs. Bij meerdere executions is dit de gemiddelde exit.
    /// `nil` voor open trades.
    public var exitPrice: Double? = nil

    /// Aantal contracten / lots (positief, ongeacht richting).
    public var quantity: Double = 1

    // MARK: - Risk management

    /// Stop loss-prijs.
    public var stopLoss: Double? = nil

    /// Take profit-prijs.
    public var takeProfit: Double? = nil

    /// Geplande risk in accountvaluta (voor R-multiple).
    /// Als `nil` en `stopLoss` gezet, wordt R afgeleid uit de stop-afstand.
    public var plannedRisk: Double? = nil

    /// Maximum Adverse Excursion (max ongunstige uitloop) in prijs-punten.
    public var mae: Double? = nil

    /// Maximum Favourable Excursion (max gunstige uitloop) in prijs-punten.
    public var mfe: Double? = nil

    // MARK: - Kosten & tick-info

    /// Totale commissie (los van de commission-velden op individuele executions).
    /// Wordt gebruikt als er geen executions zijn.
    public var commission: Double = 0

    /// Overige fees (exchange, NFA, etc.).
    public var fees: Double = 0

    /// Snapshot van de tick-grootte op het moment van invoeren.
    /// Zo blijven historische P&L-berekeningen stabiel wanneer een `Instrument`-preset
    /// later gewijzigd wordt.
    public var tickSize: Double = 0.01

    /// Snapshot van de dollarwaarde per tick per contract.
    public var tickValue: Double = 1

    // MARK: - Kwalitatief

    /// Emotie vóór de trade (vrije tekst, kort houden).
    public var emotionBefore: String = ""

    /// Emotie na de trade.
    public var emotionAfter: String = ""

    /// Rating 1..5 (0 = niet beoordeeld).
    public var rating: Int = 0

    /// Notities in markdown/plain text.
    public var notes: String = ""

    /// Vlag: is dit een backtest-trade? (Redundant met account.type maar handig voor snelfilters.)
    public var isBacktest: Bool = false

    /// Automatisch bepaalde sessie (kan bij het opslaan (her)berekend worden).
    /// Ruwe waarde van `Session`. Gebruik `session` in code.
    public var sessionRaw: String = Session.other.rawValue

    // MARK: - Relaties

    public var account: Account?
    public var instrument: Instrument?
    public var playbook: Playbook?

    @Relationship(deleteRule: .cascade, inverse: \TradeExecution.trade)
    public var executions: [TradeExecution] = []

    @Relationship(deleteRule: .cascade, inverse: \TradeScreenshot.trade)
    public var screenshots: [TradeScreenshot] = []

    @Relationship(deleteRule: .cascade, inverse: \PlaybookRuleAdherence.trade)
    public var ruleAdherence: [PlaybookRuleAdherence] = []

    @Relationship
    public var confluences: [Confluence] = []

    @Relationship
    public var tags: [Tag] = []

    @Relationship
    public var mistakes: [Mistake] = []

    // MARK: - Init

    public init(
        id: UUID = UUID(),
        symbol: String,
        direction: TradeDirection,
        entryDate: Date,
        exitDate: Date? = nil,
        entryPrice: Double,
        exitPrice: Double? = nil,
        quantity: Double,
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
        session: Session = .other,
        account: Account? = nil,
        instrument: Instrument? = nil,
        playbook: Playbook? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.symbol = symbol
        self.directionRaw = direction.rawValue
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
        self.sessionRaw = session.rawValue
        self.account = account
        self.instrument = instrument
        self.playbook = playbook
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Getypte accessors

    public var direction: TradeDirection {
        get { TradeDirection(rawValue: directionRaw) ?? .long }
        set { directionRaw = newValue.rawValue }
    }

    public var session: Session {
        get { Session(rawValue: sessionRaw) ?? .other }
        set { sessionRaw = newValue.rawValue }
    }

    /// True als de trade nog open is (geen `exitDate` én geen `exitPrice`).
    public var isOpen: Bool {
        exitDate == nil && exitPrice == nil && executions.filter({ $0.isExit(for: direction) }).isEmpty
    }

    /// Duur van de trade in seconden. `nil` als de trade nog open is.
    public var durationSeconds: TimeInterval? {
        guard let exitDate else { return nil }
        return exitDate.timeIntervalSince(entryDate)
    }
}
