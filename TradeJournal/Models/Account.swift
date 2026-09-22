import Foundation
import SwiftData

/// Een handelsaccount waaronder trades worden gejournalled.
/// Kan een prop firm-, live-, demo- of backtestaccount zijn.
@Model
public final class Account {

    /// Stabiele identifier (los van SwiftData's persistent id).
    public var id: UUID = UUID()

    /// Weergavenaam (bijv. "Topstep 50k combine #3").
    public var name: String = ""

    /// Ruwe waarde van `AccountType`. Gebruik de computed `type` in code.
    public var typeRaw: String = AccountType.demo.rawValue

    /// Startbalans in de accountvaluta.
    public var startingBalance: Double = 0

    /// Broker of prop firm (vrije tekst).
    public var broker: String = ""

    /// ISO 4217-code (USD, EUR, GBP, ...).
    public var currency: String = "USD"

    /// Optionele max. drawdown-limiet voor prop firm-accounts, in $.
    public var maxDrawdown: Double? = nil

    /// Optionele daily loss limit voor prop firm-accounts, in $.
    public var dailyLossLimit: Double? = nil

    /// Optioneel maandelijks P&L-doel (voor de dashboard voortgangsbalk).
    public var monthlyProfitTarget: Double? = nil

    /// Aanmaakmoment (voor sortering en migraties).
    public var createdAt: Date = Date()

    /// Optionele archivering — gearchiveerde accounts worden verborgen maar behouden.
    public var isArchived: Bool = false

    /// Alle trades die aan dit account gekoppeld zijn.
    @Relationship(deleteRule: .cascade, inverse: \Trade.account)
    public var trades: [Trade] = []

    public init(
        id: UUID = UUID(),
        name: String,
        type: AccountType,
        startingBalance: Double,
        broker: String = "",
        currency: String = "USD",
        maxDrawdown: Double? = nil,
        dailyLossLimit: Double? = nil,
        monthlyProfitTarget: Double? = nil,
        createdAt: Date = Date(),
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.typeRaw = type.rawValue
        self.startingBalance = startingBalance
        self.broker = broker
        self.currency = currency
        self.maxDrawdown = maxDrawdown
        self.dailyLossLimit = dailyLossLimit
        self.monthlyProfitTarget = monthlyProfitTarget
        self.createdAt = createdAt
        self.isArchived = isArchived
    }

    /// Getypte accessor voor `typeRaw`.
    public var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .demo }
        set { typeRaw = newValue.rawValue }
    }
}
