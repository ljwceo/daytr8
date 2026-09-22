import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class TradeEditingServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let service = TradeEditingService()

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    @discardableResult
    private func makeAccount(name: String = "Demo") -> Account {
        let account = Account(name: name, type: .demo, startingBalance: 50_000)
        context.insert(account)
        return account
    }

    @discardableResult
    private func makePlaybook(ruleTexts: [String]) -> Playbook {
        let playbook = Playbook(name: "Silver Bullet")
        context.insert(playbook)
        for (idx, text) in ruleTexts.enumerated() {
            let rule = PlaybookRule(text: text, sortOrder: idx)
            rule.playbook = playbook
            context.insert(rule)
            playbook.rules.append(rule)
        }
        return playbook
    }

    @discardableResult
    private func makeConfluence(name: String) -> Confluence {
        let confluence = Confluence(name: name, category: .liquidity)
        context.insert(confluence)
        return confluence
    }

    // MARK: - createTrade

    func test_createTrade_insertsTradeWithFields() throws {
        let account = makeAccount()
        var values = TradeEditingService.FormValues()
        values.account = account
        values.symbol = "NQ"
        values.direction = .long
        values.entryDate = Date(timeIntervalSince1970: 1_720_000_000)
        values.entryPrice = 18_000
        values.quantity = 2
        values.tickSize = 0.25
        values.tickValue = 5.0

        let trade = service.createTrade(from: values, in: context)

        XCTAssertEqual(trade.symbol, "NQ")
        XCTAssertEqual(trade.account, account)
        XCTAssertEqual(trade.quantity, 2)
        let stored = try context.fetch(FetchDescriptor<Trade>())
        XCTAssertTrue(stored.contains { $0.id == trade.id })
    }

    func test_createTrade_recomputesSessionFromEntryDate() throws {
        var values = TradeEditingService.FormValues()
        values.symbol = "NQ"
        // 09:30 in New York → NY AM-sessie.
        var components = DateComponents()
        components.year = 2024; components.month = 6; components.day = 3
        components.hour = 9; components.minute = 30
        components.timeZone = TimeZone(identifier: "America/New_York")
        let date = Calendar(identifier: .gregorian).date(from: components)!
        values.entryDate = date
        values.entryPrice = 100

        let trade = service.createTrade(from: values, in: context)

        XCTAssertEqual(trade.session, .nyAM)
    }

    func test_createTrade_assignsConfluencesTagsAndRuleAdherence() throws {
        let playbook = makePlaybook(ruleTexts: ["Regel A", "Regel B"])
        let confluence = makeConfluence(name: "Sweep PDL")
        let tag = Tag(name: "A+")
        context.insert(tag)
        let followedRule = playbook.rules[0]

        var values = TradeEditingService.FormValues()
        values.symbol = "NQ"
        values.entryPrice = 100
        values.playbook = playbook
        values.confluences = [confluence]
        values.tags = [tag]
        values.followedRuleIDs = [followedRule.id]

        let trade = service.createTrade(from: values, in: context)

        XCTAssertEqual(trade.confluences.map(\.id), [confluence.id])
        XCTAssertEqual(trade.tags.map(\.id), [tag.id])
        XCTAssertEqual(trade.ruleAdherence.count, 2)
        let followed = trade.ruleAdherence.filter(\.followed)
        XCTAssertEqual(followed.count, 1)
        XCTAssertEqual(followed.first?.rule?.id, followedRule.id)
    }

    // MARK: - update

    func test_update_replacesFieldsAndRuleAdherenceForNewPlaybook() throws {
        let playbookA = makePlaybook(ruleTexts: ["A1", "A2"])
        let playbookB = makePlaybook(ruleTexts: ["B1"])

        var values = TradeEditingService.FormValues()
        values.symbol = "NQ"
        values.entryPrice = 100
        values.playbook = playbookA
        values.followedRuleIDs = Set(playbookA.rules.map(\.id))
        let trade = service.createTrade(from: values, in: context)
        XCTAssertEqual(trade.ruleAdherence.count, 2)

        var updated = service.values(from: trade)
        updated.symbol = "MNQ"
        updated.playbook = playbookB
        updated.followedRuleIDs = [playbookB.rules[0].id]

        service.update(trade, with: updated, in: context)

        XCTAssertEqual(trade.symbol, "MNQ")
        XCTAssertEqual(trade.ruleAdherence.count, 1)
        XCTAssertEqual(trade.ruleAdherence.first?.rule?.id, playbookB.rules[0].id)
        XCTAssertTrue(trade.ruleAdherence.first?.followed ?? false)
    }

    // MARK: - duplicate

    func test_duplicate_copiesSetupButClearsResultFields() throws {
        let account = makeAccount()
        let confluence = makeConfluence(name: "IFVG")

        var values = TradeEditingService.FormValues()
        values.account = account
        values.symbol = "NQ"
        values.direction = .short
        values.entryPrice = 18_000
        values.exitDate = Date()
        values.exitPrice = 17_950
        values.quantity = 3
        values.confluences = [confluence]
        values.notes = "Mooie sweep"
        values.rating = 4
        let original = service.createTrade(from: values, in: context)

        let copy = service.duplicate(original, in: context)

        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.symbol, "NQ")
        XCTAssertEqual(copy.direction, .short)
        XCTAssertEqual(copy.quantity, 3)
        XCTAssertEqual(copy.account, account)
        XCTAssertEqual(copy.confluences.map(\.id), [confluence.id])
        XCTAssertNil(copy.exitDate)
        XCTAssertNil(copy.exitPrice)
        XCTAssertEqual(copy.notes, "")
        XCTAssertEqual(copy.rating, 0)
        XCTAssertTrue(copy.isOpen)
    }

    // MARK: - delete

    func test_delete_removesTradeAndCascadedScreenshots() throws {
        var values = TradeEditingService.FormValues()
        values.symbol = "NQ"
        values.entryPrice = 100
        let trade = service.createTrade(from: values, in: context)
        service.addScreenshot(Data([0x1]), to: trade, in: context)
        XCTAssertEqual(trade.screenshots.count, 1)

        service.delete(trade, from: context)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Trade>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TradeScreenshot>()).count, 0)
    }

    // MARK: - screenshots

    func test_addAndRemoveScreenshot() throws {
        var values = TradeEditingService.FormValues()
        values.symbol = "NQ"
        values.entryPrice = 100
        let trade = service.createTrade(from: values, in: context)

        let shot = service.addScreenshot(Data([0x1, 0x2]), caption: "Entry", to: trade, in: context)
        XCTAssertEqual(trade.screenshots.count, 1)
        XCTAssertEqual(shot.caption, "Entry")

        service.removeScreenshot(shot, from: trade, in: context)
        XCTAssertEqual(trade.screenshots.count, 0)
    }

    // MARK: - makeDefault

    func test_makeDefault_basedOnLastTrade_carriesSetupButClearsResult() throws {
        let account = makeAccount()
        let playbook = makePlaybook(ruleTexts: ["A1"])
        var values = TradeEditingService.FormValues()
        values.account = account
        values.symbol = "ES"
        values.direction = .short
        values.quantity = 4
        values.entryPrice = 5_000
        values.playbook = playbook
        let last = service.createTrade(from: values, in: context)

        let defaults = TradeEditingService.FormValues.makeDefault(basedOn: last, fallbackAccount: nil)

        XCTAssertEqual(defaults.account, account)
        XCTAssertEqual(defaults.symbol, "ES")
        XCTAssertEqual(defaults.direction, .short)
        XCTAssertEqual(defaults.quantity, 4)
        XCTAssertEqual(defaults.playbook, playbook)
        XCTAssertEqual(defaults.entryPrice, 0)
        XCTAssertNil(defaults.exitDate)
    }

    func test_makeDefault_withoutLastTrade_usesFallbackAccount() {
        let fallback = makeAccount(name: "Fallback")

        let defaults = TradeEditingService.FormValues.makeDefault(basedOn: nil, fallbackAccount: fallback)

        XCTAssertEqual(defaults.account, fallback)
        XCTAssertEqual(defaults.symbol, "")
    }
}
