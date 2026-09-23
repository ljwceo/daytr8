import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class ConfluenceSettingsViewModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let viewModel = ConfluenceSettingsViewModel()

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    private func all() throws -> [Confluence] {
        try context.fetch(FetchDescriptor<Confluence>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    private func draft(_ name: String, _ category: ConfluenceCategory = .other) -> ConfluenceSettingsViewModel.Draft {
        var draft = ConfluenceSettingsViewModel.Draft(category: category)
        draft.name = name
        return draft
    }

    func test_save_addsCustomConfluenceAtEndOfCategory() throws {
        SeedService.seedDefaultsIfNeeded(in: context)
        let saved = try XCTUnwrap(viewModel.save(draft("  Judas swing  ", .time), existing: nil, all: try all(), in: context))

        XCTAssertEqual(saved.name, "Judas swing")
        XCTAssertEqual(saved.category, .time)
        XCTAssertFalse(saved.isBuiltIn)
        XCTAssertTrue(saved.isActive)
        let timeItems = try all().filter { $0.category == .time }
        XCTAssertEqual(timeItems.last?.name, "Judas swing")
        XCTAssertEqual(try all().count, DefaultConfluences.all.count + 1)
    }

    func test_save_rejectsEmptyAndDuplicateNames() throws {
        SeedService.seedDefaultsIfNeeded(in: context)
        XCTAssertNotNil(viewModel.nameError(for: draft("   "), existing: nil, all: try all()))
        XCTAssertNotNil(viewModel.nameError(for: draft("sweep pdl"), existing: nil, all: try all()))
        XCTAssertNil(viewModel.save(draft("SWEEP PDL"), existing: nil, all: try all(), in: context))
        XCTAssertEqual(try all().count, DefaultConfluences.all.count)
    }

    func test_save_editsExistingIncludingBuiltIn() throws {
        SeedService.seedDefaultsIfNeeded(in: context)
        let fvg = try XCTUnwrap(try all().first { $0.name == "FVG" })

        var edit = ConfluenceSettingsViewModel.Draft(from: fvg)
        // Eigen naam mag (hij botst niet met zichzelf).
        XCTAssertNil(viewModel.nameError(for: edit, existing: fvg, all: try all()))
        edit.name = "Fair Value Gap"
        edit.colorHex = "#F2C94C"
        edit.iconName = "star"
        edit.category = .structure
        viewModel.save(edit, existing: fvg, all: try all(), in: context)

        XCTAssertEqual(fvg.name, "Fair Value Gap")
        XCTAssertEqual(fvg.colorHex, "#F2C94C")
        XCTAssertEqual(fvg.iconName, "star")
        XCTAssertEqual(fvg.category, .structure)
        XCTAssertEqual(try all().filter { $0.category == .structure }.last?.name, "Fair Value Gap")
    }

    func test_delete_removesFromTradeAndIsNotReseeded() throws {
        SeedService.seedDefaultsIfNeeded(in: context)
        let sweep = try XCTUnwrap(try all().first { $0.name == "Sweep PDL" })
        let trade = Trade(symbol: "NQ", direction: .long, entryDate: Date(), entryPrice: 100, quantity: 1)
        context.insert(trade)
        trade.confluences = [sweep]
        try context.save()

        viewModel.delete(sweep, in: context)
        try context.save()

        XCTAssertTrue(trade.confluences.isEmpty)
        XCTAssertFalse(try all().contains { $0.name == "Sweep PDL" })

        // Volgende app-start: de verwijderde standaardconfluence blijft weg.
        SeedService.seedDefaultsIfNeeded(in: context)
        XCTAssertFalse(try all().contains { $0.name == "Sweep PDL" })

        // Tot de gebruiker de standaardset terugzet.
        XCTAssertEqual(viewModel.restoreDefaults(in: context), 1)
        XCTAssertTrue(try all().contains { $0.name == "Sweep PDL" && $0.isBuiltIn })
        XCTAssertEqual(viewModel.restoreDefaults(in: context), 0)
    }

    func test_setActive_archivesAndReactivates() throws {
        let custom = try XCTUnwrap(viewModel.save(draft("Eigen"), existing: nil, all: [], in: context))
        viewModel.setActive(custom, false)
        XCTAssertFalse(custom.isActive)
        viewModel.setActive(custom, true)
        XCTAssertTrue(custom.isActive)
    }

    func test_move_reordersWithinCategory() throws {
        SeedService.seedDefaultsIfNeeded(in: context)
        let bias = try all().filter { $0.category == .bias }
        let names = bias.map(\.name)

        viewModel.move(bias, from: IndexSet(integer: 0), to: bias.count)

        let reordered = try all().filter { $0.category == .bias }.map(\.name)
        XCTAssertEqual(reordered, Array(names.dropFirst()) + [names[0]])
        // Andere categorieën blijven erachter.
        XCTAssertLessThan(try all().filter { $0.category == .bias }.map(\.sortOrder).max()!,
                          try all().filter { $0.category == .pdArrays }.map(\.sortOrder).min()!)
    }
}
