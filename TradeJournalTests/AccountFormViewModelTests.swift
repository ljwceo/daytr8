import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class AccountFormViewModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    func test_create_savesGoalsAndTreatsZeroAsUnset() throws {
        let viewModel = AccountFormViewModel(mode: .create)
        XCTAssertFalse(viewModel.isValid)

        viewModel.draft.name = "  Apex 100k "
        viewModel.draft.type = .propFirm
        viewModel.draft.startingBalance = 100_000
        viewModel.draft.monthlyProfitTarget = 3_000
        viewModel.draft.dailyLossLimit = 0
        viewModel.draft.maxDrawdown = 2_500

        let account = try XCTUnwrap(viewModel.save(in: context))
        XCTAssertEqual(account.name, "Apex 100k")
        XCTAssertEqual(account.monthlyProfitTarget, 3_000)
        XCTAssertNil(account.dailyLossLimit)
        XCTAssertEqual(account.maxDrawdown, 2_500)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Account>()), 1)
    }

    func test_edit_updatesExistingAccount() throws {
        let account = Account(name: "Live", type: .live, startingBalance: 10_000, dailyLossLimit: 300)
        context.insert(account)

        let viewModel = AccountFormViewModel(mode: .edit(account))
        XCTAssertEqual(viewModel.draft.dailyLossLimit, 300)
        viewModel.draft.type = .backtest
        viewModel.draft.isArchived = true
        viewModel.save(in: context)

        XCTAssertEqual(account.type, .backtest)
        XCTAssertTrue(account.isArchived)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Account>()), 1)
    }

    func test_validation_rejectsNegativeValues() {
        let viewModel = AccountFormViewModel(mode: .create)
        viewModel.draft.name = "X"
        viewModel.draft.maxDrawdown = -1
        XCTAssertFalse(viewModel.isValid)
        XCTAssertEqual(viewModel.validationErrors, ["Max drawdown kan niet negatief zijn."])
    }
}
