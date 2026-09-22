import XCTest
@testable import TradeJournal

final class InstrumentPresetsTests: XCTestCase {

    func test_containsRequiredSymbols() {
        let symbols = InstrumentPresets.all.map { $0.symbol }
        for expected in ["NQ", "MNQ", "ES", "MES", "YM", "GC", "CL"] {
            XCTAssertTrue(symbols.contains(expected), "Ontbrekende preset: \(expected)")
        }
        // Forex-paren
        for expected in ["EURUSD", "GBPUSD", "USDJPY"] {
            XCTAssertTrue(symbols.contains(expected), "Ontbrekende forex-preset: \(expected)")
        }
    }

    func test_NQ_tickValues_matchCMESpec() throws {
        let nq = try XCTUnwrap(InstrumentPresets.definition(for: "NQ"))
        XCTAssertEqual(nq.tickSize, 0.25, accuracy: 1e-9)
        XCTAssertEqual(nq.tickValue, 5.00, accuracy: 1e-9)
        XCTAssertEqual(nq.category, .future)
    }

    func test_MNQ_isMicroFuture_withOneTenthTickValue() throws {
        let mnq = try XCTUnwrap(InstrumentPresets.definition(for: "MNQ"))
        XCTAssertEqual(mnq.tickSize, 0.25, accuracy: 1e-9)
        XCTAssertEqual(mnq.tickValue, 0.50, accuracy: 1e-9)
        XCTAssertEqual(mnq.category, .microFuture)
    }

    func test_ES_and_MES_tickValues() throws {
        let es = try XCTUnwrap(InstrumentPresets.definition(for: "ES"))
        let mes = try XCTUnwrap(InstrumentPresets.definition(for: "MES"))
        XCTAssertEqual(es.tickValue, 12.50, accuracy: 1e-9)
        XCTAssertEqual(mes.tickValue, 1.25, accuracy: 1e-9)
    }

    func test_symbolsAreUnique() {
        let symbols = InstrumentPresets.all.map { $0.symbol }
        XCTAssertEqual(Set(symbols).count, symbols.count, "Presets moeten unieke symbolen hebben")
    }

    func test_makeInstruments_marksAllAsBuiltIn() {
        let insts = InstrumentPresets.makeInstruments()
        XCTAssertFalse(insts.isEmpty)
        for inst in insts {
            XCTAssertTrue(inst.isBuiltIn, "Preset \(inst.symbol) hoort isBuiltIn=true te hebben")
        }
    }

    func test_pointValue_computation() throws {
        let nq = try XCTUnwrap(InstrumentPresets.definition(for: "NQ"))
        // point value = tickValue / tickSize = 5 / 0.25 = 20
        XCTAssertEqual(nq.tickValue / nq.tickSize, 20, accuracy: 1e-9)

        let cl = try XCTUnwrap(InstrumentPresets.definition(for: "CL"))
        // 10 / 0.01 = 1000
        XCTAssertEqual(cl.tickValue / cl.tickSize, 1_000, accuracy: 1e-9)
    }

    func test_definitionLookup_isCaseInsensitive() {
        XCTAssertNotNil(InstrumentPresets.definition(for: "nq"))
        XCTAssertNotNil(InstrumentPresets.definition(for: "eurusd"))
        XCTAssertNil(InstrumentPresets.definition(for: "DOESNOTEXIST"))
    }
}
