import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class ProgressTrackerViewModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2 // maandag
        return cal
    }()

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func makeViewModel(today: Date) -> ProgressTrackerViewModel {
        ProgressTrackerViewModel(calendar: calendar, today: today)
    }

    func test_heatmapWeeks_endsInCurrentWeekAndHidesFutureDays() {
        // Woensdag 23 september 2026.
        let today = date(9, 23)
        let weeks = makeViewModel(today: today).heatmapWeeks(endingOn: today, weeks: 3)

        XCTAssertEqual(weeks.count, 3)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        // Eerste kolom begint op maandag 7 september.
        XCTAssertEqual(weeks[0][0], date(9, 7, 0))
        // Laatste kolom: ma 21, di 22, wo 23, daarna toekomst.
        XCTAssertEqual(weeks[2][0], date(9, 21, 0))
        XCTAssertEqual(weeks[2][2], date(9, 23, 0))
        XCTAssertNil(weeks[2][3])
        XCTAssertNil(weeks[2][6])
    }

    func test_toggleCheck_createsThenToggles() throws {
        let viewModel = makeViewModel(today: date(9, 23))
        let rule = DailyRule(name: "A+ only", kind: .manual, createdAt: date(9, 1))
        context.insert(rule)

        viewModel.toggleCheck(for: rule, on: date(9, 23, 9), in: context)
        XCTAssertEqual(rule.checks.count, 1)
        XCTAssertEqual(rule.checks.first?.isFollowed, true)
        XCTAssertEqual(rule.checks.first?.date, date(9, 23, 0))

        viewModel.toggleCheck(for: rule, on: date(9, 23, 17), in: context)
        XCTAssertEqual(rule.checks.count, 1)
        XCTAssertEqual(rule.checks.first?.isFollowed, false)

        let checks = try context.fetch(FetchDescriptor<DailyRuleCheck>())
        let progress = viewModel.dayProgress(for: date(9, 23), rules: [rule], trades: [], journals: [], checks: checks)
        XCTAssertFalse(progress.isPerfect)
        XCTAssertTrue(progress.isTracked)
    }

    func test_saveRule_createNewAndEdit() throws {
        let viewModel = makeViewModel(today: date(9, 23))
        var draft = ProgressTrackerViewModel.RuleDraft()
        draft.name = "  Max 2 trades "
        draft.kind = .maxTrades
        draft.threshold = 2

        let rule = try XCTUnwrap(viewModel.saveRule(draft, existing: nil, allRules: [], in: context, now: date(9, 23)))
        XCTAssertEqual(rule.name, "Max 2 trades")
        XCTAssertEqual(rule.threshold, 2)
        XCTAssertEqual(rule.createdAt, date(9, 23))

        // Wisselen naar een soort zonder grens zet de grens op 0.
        var edit = ProgressTrackerViewModel.RuleDraft(from: rule)
        edit.kind = .journalFilled
        viewModel.saveRule(edit, existing: rule, allRules: [rule], in: context)
        XCTAssertEqual(rule.kind, .journalFilled)
        XCTAssertEqual(rule.threshold, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyRule>()), 1)
    }

    func test_ruleDraft_validation() {
        var draft = ProgressTrackerViewModel.RuleDraft()
        XCTAssertFalse(draft.isValid)
        draft.name = "Max trades"
        draft.kind = .maxTrades
        draft.threshold = 0
        XCTAssertFalse(draft.isValid)
        draft.threshold = 3
        XCTAssertTrue(draft.isValid)
    }

    func test_moveRules_updatesSortOrder() {
        let viewModel = makeViewModel(today: date(9, 23))
        let rules = (0..<4).map { index -> DailyRule in
            let rule = DailyRule(name: "R\(index)", kind: .manual, sortOrder: index)
            context.insert(rule)
            return rule
        }
        // R0 naar het einde.
        viewModel.moveRules(rules, from: IndexSet(integer: 0), to: 4)
        XCTAssertEqual(rules.sorted { $0.sortOrder < $1.sortOrder }.map(\.name), ["R1", "R2", "R3", "R0"])

        // R3 (nu index 2) naar het begin.
        let current = rules.sorted { $0.sortOrder < $1.sortOrder }
        viewModel.moveRules(current, from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(rules.sorted { $0.sortOrder < $1.sortOrder }.map(\.name), ["R3", "R1", "R2", "R0"])
    }
}
