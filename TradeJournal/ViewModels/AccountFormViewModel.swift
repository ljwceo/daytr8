import Foundation
import SwiftData

/// Aanmaken/bewerken van een `Account`, inclusief de doelen en limieten
/// (maandelijks P&L-doel, daily loss limit, max drawdown) uit SPEC §10.
@Observable
public final class AccountFormViewModel {

    public enum Mode {
        case create
        case edit(Account)
    }

    /// Bewerkbare velden, los van SwiftData.
    public struct Draft: Equatable {
        public var name: String = ""
        public var type: AccountType = .propFirm
        public var startingBalance: Double = 50_000
        public var broker: String = ""
        public var currency: String = "USD"
        public var monthlyProfitTarget: Double? = nil
        public var dailyLossLimit: Double? = nil
        public var maxDrawdown: Double? = nil
        public var isArchived: Bool = false

        public init() {}

        public init(from account: Account) {
            name = account.name
            type = account.type
            startingBalance = account.startingBalance
            broker = account.broker
            currency = account.currency
            monthlyProfitTarget = account.monthlyProfitTarget
            dailyLossLimit = account.dailyLossLimit
            maxDrawdown = account.maxDrawdown
            isArchived = account.isArchived
        }
    }

    public static let currencies = ["USD", "EUR", "GBP", "CHF", "JPY", "AUD", "CAD"]

    public let mode: Mode
    public var draft: Draft

    public init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create: draft = Draft()
        case .edit(let account): draft = Draft(from: account)
        }
    }

    public var title: String {
        if case .edit = mode { return "Account bewerken" }
        return "Nieuw account"
    }

    public var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    public var validationErrors: [String] {
        var errors: [String] = []
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Geef het account een naam.")
        }
        if draft.startingBalance < 0 {
            errors.append("De startbalans kan niet negatief zijn.")
        }
        for (label, value) in [("Maanddoel", draft.monthlyProfitTarget), ("Daily loss limit", draft.dailyLossLimit), ("Max drawdown", draft.maxDrawdown)] {
            if let value, value < 0 { errors.append("\(label) kan niet negatief zijn.") }
        }
        return errors
    }

    public var isValid: Bool { validationErrors.isEmpty }

    /// Slaat het concept op. Een doel of limiet van 0 wordt als "niet
    /// ingesteld" (`nil`) bewaard.
    @discardableResult
    public func save(in context: ModelContext) -> Account? {
        guard isValid else { return nil }
        let account: Account
        switch mode {
        case .create:
            account = Account(name: "", type: draft.type, startingBalance: 0)
            context.insert(account)
        case .edit(let existing):
            account = existing
        }
        account.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.type = draft.type
        account.startingBalance = draft.startingBalance
        account.broker = draft.broker.trimmingCharacters(in: .whitespacesAndNewlines)
        account.currency = draft.currency
        account.monthlyProfitTarget = Self.positive(draft.monthlyProfitTarget)
        account.dailyLossLimit = Self.positive(draft.dailyLossLimit)
        account.maxDrawdown = Self.positive(draft.maxDrawdown)
        account.isArchived = draft.isArchived
        return account
    }

    /// Verwijdert het account inclusief al zijn trades (cascade).
    public static func delete(_ account: Account, in context: ModelContext) {
        context.delete(account)
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
