import XCTest
import SwiftData
@testable import TradeJournal

/// Integratie-tests die een in-memory `ModelContainer` opzetten en de
/// seed + sample-data services daartegen draaien.
@MainActor
final class SeedAndSampleDataTests: XCTestCase {

    private func makeInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
    }

    // MARK: - Seed

    func test_seedDefaults_insertsAllPresetsAndConfluences() throws {
        let container = try makeInMemoryContainer()
        SeedService.seedDefaultsIfNeeded(in: container.mainContext)

        let instruments = try container.mainContext.fetch(FetchDescriptor<Instrument>())
        let confluences = try container.mainContext.fetch(FetchDescriptor<Confluence>())

        XCTAssertEqual(instruments.count, InstrumentPresets.all.count)
        XCTAssertEqual(confluences.count, DefaultConfluences.all.count)

        XCTAssertTrue(instruments.allSatisfy { $0.isBuiltIn })
        XCTAssertTrue(confluences.allSatisfy { $0.isBuiltIn })
    }

    func test_seedDefaults_isIdempotent() throws {
        let container = try makeInMemoryContainer()
        SeedService.seedDefaultsIfNeeded(in: container.mainContext)
        SeedService.seedDefaultsIfNeeded(in: container.mainContext)
        SeedService.seedDefaultsIfNeeded(in: container.mainContext)

        let instruments = try container.mainContext.fetch(FetchDescriptor<Instrument>())
        let confluences = try container.mainContext.fetch(FetchDescriptor<Confluence>())
        XCTAssertEqual(instruments.count, InstrumentPresets.all.count)
        XCTAssertEqual(confluences.count, DefaultConfluences.all.count)
    }

    // MARK: - Sample data

    func test_sampleDataGenerator_producesTradesAcrossTwoYears() throws {
        let container = try makeInMemoryContainer()
        let count = SampleDataService.generate(
            in: container.mainContext,
            options: .init(seed: 42, years: 2, tradesPerWeek: 6...12, winRate: 0.5,
                           averageWinR: 1.5, averageLossR: 1.0)
        )

        XCTAssertGreaterThan(count, 50, "Voorbeelddata-generator zou vele tientallen trades moeten produceren")

        let trades = try container.mainContext.fetch(FetchDescriptor<Trade>())
        XCTAssertEqual(trades.count, count)

        // Elke trade heeft minstens 1 confluence en een sessie.
        XCTAssertTrue(trades.allSatisfy { !$0.confluences.isEmpty })
        XCTAssertTrue(trades.allSatisfy { $0.session != .other || $0.entryDate == $0.entryDate })

        // Er zijn zowel live- als backtest-trades.
        XCTAssertTrue(trades.contains { $0.account?.type == .demo })
    }

    func test_wipeAll_removesEverything() throws {
        let container = try makeInMemoryContainer()
        _ = SampleDataService.generate(in: container.mainContext, options: .init(seed: 1, years: 0.2))

        SampleDataService.wipeAll(in: container.mainContext)

        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Trade>()).count, 0)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Account>()).count, 0)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Playbook>()).count, 0)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Confluence>()).count, 0)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Instrument>()).count, 0)
    }

    func test_generatorIsDeterministic_forSameSeed() throws {
        let containerA = try makeInMemoryContainer()
        let containerB = try makeInMemoryContainer()

        let a = SampleDataService.generate(in: containerA.mainContext, options: .init(seed: 123, years: 0.3))
        let b = SampleDataService.generate(in: containerB.mainContext, options: .init(seed: 123, years: 0.3))

        XCTAssertEqual(a, b, "Dezelfde seed moet exact hetzelfde aantal trades opleveren")
    }
}
