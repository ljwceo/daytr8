import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class JournalTemplateServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let service = JournalTemplateService()
    private let utc = TimeZone(identifier: "UTC")!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    /// Dinsdag 22 september 2026, 12:00 UTC.
    private let date = Date(timeIntervalSince1970: 1_790_078_400)

    private func templates() throws -> [JournalTemplate] {
        try context.fetch(FetchDescriptor<JournalTemplate>())
    }

    // MARK: - Toepassen

    func test_render_replacesDatePlaceholder() {
        XCTAssertEqual(service.render("Review — {{datum}}", for: date, timeZone: utc), "Review — dinsdag 22 september 2026")
        XCTAssertEqual(service.render("Geen placeholder", for: date, timeZone: utc), "Geen placeholder")
    }

    func test_apply_emptyField_getsTemplate() {
        XCTAssertEqual(service.apply("Bias:", to: "  \n", date: date, timeZone: utc), "Bias:")
    }

    func test_apply_appendsAfterExistingText_andDoesNotDuplicate() {
        let once = service.apply("Bias:", to: "Eigen notitie", date: date, timeZone: utc)
        XCTAssertEqual(once, "Eigen notitie\n\nBias:")
        XCTAssertEqual(service.apply("Bias:", to: once, date: date, timeZone: utc), once)
    }

    // MARK: - Beheer

    func test_create_firstOfKindBecomesDefault() throws {
        let first = service.create(kind: .preMarket, name: "Plan A", body: "A", in: context)
        let second = service.create(kind: .preMarket, name: "Plan B", body: "B", in: context)
        let post = service.create(kind: .postMarket, name: "Review", body: "R", in: context)

        XCTAssertTrue(first.isDefault)
        XCTAssertFalse(second.isDefault)
        XCTAssertTrue(post.isDefault)
        XCTAssertEqual(second.sortOrder, first.sortOrder + 1)
        XCTAssertEqual(service.defaultTemplate(for: .preMarket, in: try templates())?.id, first.id)
    }

    func test_setDefault_movesFlagWithinKindOnly() throws {
        let first = service.create(kind: .preMarket, name: "Plan A", body: "A", in: context)
        let second = service.create(kind: .preMarket, name: "Plan B", body: "B", in: context)
        let post = service.create(kind: .postMarket, name: "Review", body: "R", in: context)

        service.setDefault(second, in: context)
        XCTAssertFalse(first.isDefault)
        XCTAssertTrue(second.isDefault)
        XCTAssertTrue(post.isDefault)
    }

    func test_delete_default_promotesNext() throws {
        let first = service.create(kind: .preMarket, name: "Plan A", body: "A", in: context)
        let second = service.create(kind: .preMarket, name: "Plan B", body: "B", in: context)
        try context.save()

        service.delete(first, in: context)
        try context.save()
        XCTAssertEqual(try templates().count, 1)
        XCTAssertTrue(second.isDefault)
    }

    func test_update_trimsName() {
        let template = service.create(kind: .postMarket, name: "Review", body: "R", in: context)
        service.update(template, name: "  Nieuwe naam ", body: "Nieuwe tekst", now: date)
        XCTAssertEqual(template.name, "Nieuwe naam")
        XCTAssertEqual(template.body, "Nieuwe tekst")
        XCTAssertEqual(template.updatedAt, date)
    }

    // MARK: - Seed

    func test_seed_isIdempotent_andRespectsExistingTemplates() throws {
        SeedService.seedJournalTemplatesIfNeeded(in: context)
        SeedService.seedJournalTemplatesIfNeeded(in: context)
        XCTAssertEqual(try templates().count, JournalTemplateService.defaults.count)
        XCTAssertTrue(try templates().allSatisfy(\.isDefault))

        // Eigen post-market-template, pre-market leeg → alleen pre-market wordt aangevuld.
        SampleDataService.wipeAll(in: context)
        service.create(kind: .postMarket, name: "Mijn review", body: "R", in: context)
        SeedService.seedJournalTemplatesIfNeeded(in: context)
        let all = try templates()
        XCTAssertEqual(all.filter { $0.kind == .postMarket }.map(\.name), ["Mijn review"])
        XCTAssertEqual(all.filter { $0.kind == .preMarket }.count, 1)
    }

    func test_seedDailyRules_onlyWhenNoRulesExist() throws {
        SeedService.seedDailyRulesIfNeeded(in: context)
        SeedService.seedDailyRulesIfNeeded(in: context)
        let rules = try context.fetch(FetchDescriptor<DailyRule>())
        XCTAssertEqual(rules.count, SeedService.defaultDailyRules.count)
        XCTAssertTrue(rules.contains { $0.kind == .maxTrades && $0.threshold == 3 })
        XCTAssertTrue(rules.contains { $0.kind == .stopAfterLosses && $0.threshold == 2 })
        XCTAssertTrue(rules.contains { $0.kind == .journalFilled })
    }
}
