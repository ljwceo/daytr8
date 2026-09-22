import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class DashboardViewModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var viewModel: DashboardViewModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
        viewModel = DashboardViewModel()
    }

    override func tearDownWithError() throws {
        container = nil
        viewModel = nil
        try super.tearDownWithError()
    }

    @discardableResult
    private func makeTrade(
        symbol: String = "NQ",
        account: Account? = nil,
        playbook: Playbook? = nil,
        confluence: Confluence? = nil,
        entryDate: Date,
        exit: Double? = 18_010,
        entry: Double = 18_000
    ) -> Trade {
        let trade = Trade(
            symbol: symbol,
            direction: .long,
            entryDate: entryDate,
            exitDate: exit == nil ? nil : entryDate.addingTimeInterval(600),
            entryPrice: entry,
            exitPrice: exit,
            quantity: 1,
            tickSize: 0.25,
            tickValue: 5.0,
            account: account,
            playbook: playbook
        )
        if let confluence { trade.confluences = [confluence] }
        context.insert(trade)
        return trade
    }

    // MARK: - Accountfilter

    func test_filteredTrades_accountFilter_keepsOnlySelectedAccounts() {
        let accountA = Account(name: "A", type: .live, startingBalance: 1000)
        let accountB = Account(name: "B", type: .demo, startingBalance: 1000)
        context.insert(accountA)
        context.insert(accountB)

        let now = Date()
        let tradeA = makeTrade(account: accountA, entryDate: now)
        makeTrade(account: accountB, entryDate: now)

        viewModel.selectedAccountIDs = [accountA.id]
        let result = viewModel.filteredTrades([tradeA])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.account?.id, accountA.id)
    }

    // MARK: - Periodefilter

    func test_filteredTrades_todayPeriod_excludesOlderTrades() {
        let now = Date()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        let today = makeTrade(entryDate: now)
        let older = makeTrade(entryDate: yesterday)

        viewModel.period = .today
        let result = viewModel.filteredTrades([today, older], now: now, calendar: calendar)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, today.id)
    }

    func test_filteredTrades_allPeriod_keepsEverything() {
        let now = Date()
        let calendar = Calendar.current
        let old = calendar.date(byAdding: .year, value: -2, to: now)!

        let recent = makeTrade(entryDate: now)
        let ancient = makeTrade(entryDate: old)

        viewModel.period = .all
        let result = viewModel.filteredTrades([recent, ancient], now: now, calendar: calendar)

        XCTAssertEqual(result.count, 2)
    }

    // MARK: - Symbool / playbook / confluence

    func test_filteredTrades_symbolFilter() {
        let now = Date()
        let nq = makeTrade(symbol: "NQ", entryDate: now)
        makeTrade(symbol: "ES", entryDate: now)

        viewModel.symbolFilter = "NQ"
        let result = viewModel.filteredTrades([nq])
        XCTAssertEqual(result.map(\.symbol), ["NQ"])
    }

    func test_filteredTrades_playbookFilter() {
        let playbook = Playbook(name: "ICT AM")
        context.insert(playbook)
        let now = Date()
        let matching = makeTrade(playbook: playbook, entryDate: now)
        makeTrade(entryDate: now)

        viewModel.playbookID = playbook.id
        let result = viewModel.filteredTrades([matching])
        XCTAssertEqual(result.count, 1)
    }

    func test_filteredTrades_confluenceFilter() {
        let confluence = Confluence(name: "Sweep PDL", category: .liquidity)
        context.insert(confluence)
        let now = Date()
        let matching = makeTrade(confluence: confluence, entryDate: now)
        makeTrade(entryDate: now)

        viewModel.confluenceID = confluence.id
        let result = viewModel.filteredTrades([matching])
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - Grafiekpunten

    func test_equityPointsAndDrawdownPoints_reflectPnLSequence() {
        let base = Date(timeIntervalSince1970: 1_720_000_000)
        let win = makeTrade(entryDate: base, exit: 18_010)
        let loss = makeTrade(entryDate: base.addingTimeInterval(3600), exit: 17_990)

        let equity = viewModel.equityPoints(for: [win, loss])
        XCTAssertEqual(equity.count, 2)
        XCTAssertEqual(equity[0].value, 200, accuracy: 0.01)
        XCTAssertEqual(equity[1].value, 0, accuracy: 0.01)

        let drawdown = viewModel.drawdownPoints(for: [win, loss])
        XCTAssertEqual(drawdown[0].value, 0, accuracy: 0.01)
        XCTAssertEqual(drawdown[1].value, -200, accuracy: 0.01)
    }

    // MARK: - Rule adherence

    func test_ruleAdherenceRate_nilWithoutAdherenceRecords() {
        let trade = makeTrade(entryDate: Date())
        XCTAssertNil(viewModel.ruleAdherenceRate(for: [trade]))
    }

    func test_ruleAdherenceRate_computesFollowedFraction() {
        let playbook = Playbook(name: "ICT AM")
        let rule1 = PlaybookRule(text: "Wacht op sweep")
        let rule2 = PlaybookRule(text: "Bevestig met IFVG")
        rule1.playbook = playbook
        rule2.playbook = playbook
        context.insert(playbook)
        context.insert(rule1)
        context.insert(rule2)

        let trade = makeTrade(playbook: playbook, entryDate: Date())
        let followed = PlaybookRuleAdherence(followed: true)
        followed.rule = rule1
        followed.trade = trade
        let notFollowed = PlaybookRuleAdherence(followed: false)
        notFollowed.rule = rule2
        notFollowed.trade = trade
        context.insert(followed)
        context.insert(notFollowed)
        trade.ruleAdherence = [followed, notFollowed]

        XCTAssertEqual(viewModel.ruleAdherenceRate(for: [trade]) ?? -1, 0.5, accuracy: 0.01)
    }

    // MARK: - Recente trades

    func test_recentTrades_sortsByMostRecentFirstAndLimits() {
        let now = Date()
        let t1 = makeTrade(entryDate: now.addingTimeInterval(-7200))
        let t2 = makeTrade(entryDate: now.addingTimeInterval(-3600))
        let t3 = makeTrade(entryDate: now)

        let recent = viewModel.recentTrades(from: [t1, t2, t3], limit: 2)
        XCTAssertEqual(recent.map(\.id), [t3.id, t2.id])
    }
}
