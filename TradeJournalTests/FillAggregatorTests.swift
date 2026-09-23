import XCTest
@testable import TradeJournal

final class FillAggregatorTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_733_400_000)

    // Symbol staat achteraan met een default zodat de meeste tests hem mogen
    // overslaan; Swift laat een defaulted `_`-parameter in het midden niet toe.
    private func fill(_ minutes: Double, _ quantity: Double, _ price: Double,
                      symbol: String = "NQ", commission: Double = 0, row: Int = 0) -> ImportedFill {
        ImportedFill(symbol: symbol, date: t0.addingTimeInterval(minutes * 60), price: price,
                     signedQuantity: quantity, commission: commission, sourceRow: row)
    }

    func test_simpleLongRoundTrip() {
        let trades = FillAggregator.aggregate([
            fill(0, 2, 21_000, commission: 1, row: 1),
            fill(5, -2, 21_010, commission: 1, row: 2)
        ])
        XCTAssertEqual(trades.count, 1)
        let trade = trades[0]
        XCTAssertEqual(trade.direction, .long)
        XCTAssertEqual(trade.quantity, 2)
        XCTAssertEqual(trade.entryPrice, 21_000)
        XCTAssertEqual(trade.exitPrice, 21_010)
        XCTAssertEqual(trade.entryDate, t0)
        XCTAssertEqual(trade.exitDate, t0.addingTimeInterval(300))
        XCTAssertEqual(trade.commission, 2)
        XCTAssertEqual(trade.fills.count, 2)
        XCTAssertEqual(trade.sourceRows, [1, 2])
    }

    func test_shortWithScaleInAndPartialExits() {
        let trades = FillAggregator.aggregate([
            fill(0, -1, 100),
            fill(1, -1, 102),        // bijschalen
            fill(2, 1, 98),          // partial exit
            fill(3, 1, 96)           // flat
        ])
        XCTAssertEqual(trades.count, 1)
        let trade = trades[0]
        XCTAssertEqual(trade.direction, .short)
        XCTAssertEqual(trade.quantity, 2)
        XCTAssertEqual(trade.entryPrice, 101, accuracy: 1e-9)
        XCTAssertEqual(trade.exitPrice ?? 0, 97, accuracy: 1e-9)
        XCTAssertFalse(trade.isOpen)
    }

    func test_positionFlipSplitsFillAndCommission() {
        let trades = FillAggregator.aggregate([
            fill(0, 1, 100, commission: 1),
            fill(1, -3, 105, commission: 3)   // 1 sluit de long, 2 openen een short
        ])
        XCTAssertEqual(trades.count, 2)

        let long = trades[0]
        XCTAssertEqual(long.direction, .long)
        XCTAssertEqual(long.quantity, 1)
        XCTAssertEqual(long.exitPrice, 105)
        XCTAssertEqual(long.commission, 2, accuracy: 1e-9)   // 1 + 1/3 van 3

        let short = trades[1]
        XCTAssertEqual(short.direction, .short)
        XCTAssertEqual(short.quantity, 2)
        XCTAssertTrue(short.isOpen)
        XCTAssertNil(short.exitDate)
        XCTAssertEqual(short.commission, 2, accuracy: 1e-9)  // 2/3 van 3
    }

    func test_separatesSymbolsAndSortsByEntry() {
        let trades = FillAggregator.aggregate([
            fill(1, 1, 5_000, symbol: "ES"),
            fill(0, 1, 21_000, symbol: "NQ"),
            fill(2, -1, 5_001, symbol: "ES"),
            fill(3, -1, 21_001, symbol: "NQ")
        ])
        XCTAssertEqual(trades.map(\.symbol), ["NQ", "ES"])
        XCTAssertTrue(trades.allSatisfy { !$0.isOpen })
    }

    func test_openPositionAtEndIsOpenTrade() {
        let trades = FillAggregator.aggregate([fill(0, 1, 100)])
        XCTAssertEqual(trades.count, 1)
        XCTAssertTrue(trades[0].isOpen)
    }

    func test_ignoresZeroQuantityFills() {
        XCTAssertTrue(FillAggregator.aggregate([fill(0, 0, 100)]).isEmpty)
    }
}
