import XCTest
import UIKit
@testable import TradeJournal

/// Van begin tot eind met echte Apple Vision-OCR: een tabel met de kolommen
/// van Tradovate, TopstepX en NinjaTrader wordt als afbeelding getekend,
/// door `VisionTextRecognizer` gelezen en door de parser omgezet. Zo testen
/// we hoe Vision de blokken werkelijk aanlevert (samengevoegde cellen,
/// posities), niet alleen de tekstfixtures.
final class ScreenshotVisionTableTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    /// Tekent `rows` als tabel: donkere achtergrond zoals de platforms, elke
    /// kolom zo breed als zijn breedste cel plus een vaste tussenruimte.
    private func renderTable(_ rows: [[String]], title: String?) -> Data {
        let font = UIFont.systemFont(ofSize: 22)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let gap: CGFloat = 48
        let rowHeight: CGFloat = 52
        let margin: CGFloat = 24
        let columnCount = rows.map(\.count).max() ?? 0
        let widths = (0..<columnCount).map { column in
            rows.map { row in column < row.count ? (row[column] as NSString).size(withAttributes: attributes).width : 0 }.max() ?? 0
        }
        var columnX: [CGFloat] = []
        var x = margin
        for width in widths {
            columnX.append(x)
            x += width + gap
        }
        let titleRows = title == nil ? 0 : 1
        let size = CGSize(width: x + margin, height: margin * 2 + rowHeight * CGFloat(rows.count + titleRows))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor(white: 0.08, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            if let title {
                (title as NSString).draw(at: CGPoint(x: margin, y: margin), withAttributes: attributes)
            }
            for (rowIndex, row) in rows.enumerated() {
                let y = margin + rowHeight * CGFloat(rowIndex + titleRows)
                for (column, cell) in row.enumerated() {
                    (cell as NSString).draw(at: CGPoint(x: columnX[column], y: y), withAttributes: attributes)
                }
            }
        }
    }

    private func recognize(_ rows: [[String]], title: String?) async throws -> (result: ScreenshotParseResult, lines: String) {
        let boxes = try await VisionTextRecognizer().recognizeBoxes(in: renderTable(rows, title: title))
        let parser = ScreenshotParser(templates: ScreenshotTemplateStore.bundledTemplates(), timeZone: utc)
        let lines = ScreenshotLineBuilder.lines(from: boxes).joined(separator: " | ")
        return (parser.parse(boxes: boxes), lines)
    }

    func test_vision_tradovatePerformanceTable() async throws {
        let (result, lines) = try await recognize([
            ["Symbol", "Qty", "Buy Price", "Sell Price", "P&L", "Bought Timestamp", "Sold Timestamp", "Duration"],
            ["MNQZ5", "2", "21450.25", "21462.75", "$50.00", "09/22/2025 09:31:22", "09/22/2025 09:45:10", "13min 48sec"],
            ["ESZ5", "1", "6650.50", "6655.00", "$225.00", "09/22/2025 10:12:40", "09/22/2025 10:02:05", "10min 35sec"]
        ], title: "Performance")

        XCTAssertEqual(result.templateID, "tradovate", lines)
        XCTAssertEqual(result.symbol?.value, "MNQ", lines)
        XCTAssertEqual(result.direction?.value, .long, lines)
        XCTAssertEqual(result.quantity?.value, 2, lines)
        XCTAssertEqual(result.entryPrice?.value, 21450.25, lines)
        XCTAssertEqual(result.exitPrice?.value, 21462.75, lines)
        XCTAssertEqual(result.grossPnL?.value, 50, lines)
        XCTAssertEqual(result.entryTime?.value, utcDate(2025, 9, 22, 9, 31, 22), lines)
        XCTAssertEqual(result.exitTime?.value, utcDate(2025, 9, 22, 9, 45, 10), lines)
        XCTAssertEqual(result.tableRows.count, 2, lines)
        XCTAssertEqual(result.tableRows.last?.symbol?.value, "ES", lines)
        XCTAssertEqual(result.tableRows.last?.direction?.value, .short, lines)
        XCTAssertEqual(result.tableRows.last?.grossPnL?.value, 225, lines)
    }

    func test_vision_topstepXTradesTable() async throws {
        let (result, lines) = try await recognize([
            ["Symbol", "Size", "Type", "Entry Time", "Exit Time", "Entry Price", "Exit Price", "P&L", "Fees"],
            ["/MNQ", "3", "Long", "09/22/2025 09:31:22", "09/22/2025 09:40:05", "21450.25", "21440.00", "-$61.50", "$2.22"],
            ["/ES", "1", "Short", "09/22/2025 10:05:00", "09/22/2025 10:20:45", "6655.00", "6650.50", "$225.00", "$2.80"]
        ], title: "Trades")

        XCTAssertEqual(result.templateID, "topstepx", lines)
        XCTAssertEqual(result.symbol?.value, "MNQ", lines)
        XCTAssertEqual(result.direction?.value, .long, lines)
        XCTAssertEqual(result.quantity?.value, 3, lines)
        XCTAssertEqual(result.entryPrice?.value, 21450.25, lines)
        XCTAssertEqual(result.exitPrice?.value, 21440, lines)
        XCTAssertEqual(result.grossPnL?.value, -61.5, lines)
        XCTAssertEqual(result.fees?.value, 2.22, lines)
        XCTAssertEqual(result.entryTime?.value, utcDate(2025, 9, 22, 9, 31, 22), lines)
        XCTAssertEqual(result.tableRows.count, 2, lines)
        XCTAssertEqual(result.tableRows.last?.direction?.value, .short, lines)
    }

    /// NinjaTrader: Vision slaat losse cellen met één cijfer over (Trade
    /// number "1", Qty "1", Bars "7"). De parser levert dan geen aantal; het
    /// formulier rekent het terug uit Profit, entry en exit met de tick
    /// size/value van de NQ-preset. Daarom ook via het formulier getest.
    private var ninjaTraderRows: [[String]] {
        [
            ["Trade number", "Instrument", "Account", "Strategy", "Market pos.", "Qty", "Entry price", "Exit price",
             "Entry time", "Exit time", "Entry name", "Exit name", "Profit", "Cum. net profit", "Commission", "MAE", "MFE", "ETD", "Bars"],
            ["1", "NQ 12-25", "Sim101", "", "Long", "1", "21450.25", "21470.50",
             "9/22/2025 9:31:22 AM", "9/22/2025 9:52:10 AM", "Entry", "Profit target", "$405.00", "$400.70", "$4.30", "$75.00", "$450.00", "$45.00", "21"],
            ["2", "NQ 12-25", "Sim101", "", "Short", "2", "21480.00", "21490.25",
             "9/22/2025 10:15:00 AM", "9/22/2025 10:21:40 AM", "Entry", "Stop loss", "($410.00)", "($18.60)", "$8.60", "$450.00", "$120.00", "$530.00", "7"]
        ]
    }

    func test_vision_ninjaTraderTradesTable() async throws {
        let (result, lines) = try await recognize(ninjaTraderRows, title: "Trade Performance")

        XCTAssertEqual(result.templateID, "ninjatrader", lines)
        XCTAssertEqual(result.symbol?.value, "NQ", lines)
        XCTAssertEqual(result.direction?.value, .long, lines)
        XCTAssertEqual(result.entryPrice?.value, 21450.25, lines)
        XCTAssertEqual(result.exitPrice?.value, 21470.5, lines)
        XCTAssertEqual(result.entryTime?.value, utcDate(2025, 9, 22, 9, 31, 22), lines)
        XCTAssertEqual(result.exitTime?.value, utcDate(2025, 9, 22, 9, 52, 10), lines)
        XCTAssertEqual(result.grossPnL?.value, 405, lines)
        XCTAssertEqual(result.commission?.value, 4.3, lines)
        XCTAssertEqual(result.tableRows.count, 2, lines)
        XCTAssertEqual(result.tableRows.last?.grossPnL?.value, -410, lines)
    }

    /// Van screenshot tot formulier: ook het aantal dat Vision overslaat
    /// komt er goed in, voor beide trades.
    @MainActor
    func test_vision_ninjaTraderTable_fillsFormIncludingQuantity() async throws {
        let viewModel = TradeFormViewModel(
            mode: .create,
            textRecognizer: VisionTextRecognizer(),
            screenshotTemplates: ScreenshotTemplateStore.bundledTemplates()
        )

        await viewModel.importScreenshot(renderTable(ninjaTraderRows, title: "Trade Performance"), instruments: [])

        XCTAssertEqual(viewModel.values.symbol, "NQ")
        XCTAssertEqual(viewModel.values.direction, .long)
        XCTAssertEqual(viewModel.values.entryPrice, 21450.25)
        XCTAssertEqual(viewModel.values.exitPrice, 21470.5)
        XCTAssertEqual(viewModel.values.quantity, 1, "Teruggerekend: 20.25 punt × $20 = $405")
        XCTAssertEqual(viewModel.values.commission, 4.3)
        XCTAssertEqual(viewModel.brokerNetPnL ?? 0, 400.7, accuracy: 0.001, "Profit − commissie")
        XCTAssertEqual(viewModel.ocrTradeCandidates.count, 2)

        viewModel.selectOCRTrade(1)

        XCTAssertEqual(viewModel.values.direction, .short)
        XCTAssertEqual(viewModel.values.quantity, 2, "10.25 punt × $20 × 2 = $410")
        XCTAssertEqual(viewModel.brokerNetPnL ?? 0, -418.6, accuracy: 0.001)
    }
}
