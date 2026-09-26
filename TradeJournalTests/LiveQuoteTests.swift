import XCTest
import SwiftData
@testable import TradeJournal

@MainActor
final class LiveQuoteTests: XCTestCase {

    // MARK: - Symbolen

    func test_resolver_futuresMapToContinuousContract() {
        XCTAssertEqual(QuoteSymbolResolver.resolve("MNQZ26")?.providerSymbol, "MNQ=F")
        XCTAssertEqual(QuoteSymbolResolver.resolve("MNQZ26")?.display, "MNQ")
        XCTAssertEqual(QuoteSymbolResolver.resolve("/MNQ")?.providerSymbol, "MNQ=F")
        XCTAssertEqual(QuoteSymbolResolver.resolve("NQ 12-26")?.providerSymbol, "NQ=F")
        XCTAssertEqual(QuoteSymbolResolver.resolve("CME_MINI:ES1!")?.providerSymbol, "ES=F")
        XCTAssertEqual(QuoteSymbolResolver.resolve("mgcz2026")?.providerSymbol, "MGC=F")
        XCTAssertEqual(QuoteSymbolResolver.resolve("MNQ")?.kind, .future)
        // Onbekende future met instrumentcategorie.
        XCTAssertEqual(QuoteSymbolResolver.resolve("6EZ26", category: .future)?.providerSymbol, "6E=F")
    }

    func test_resolver_forexIndexStockCrypto() {
        XCTAssertEqual(QuoteSymbolResolver.resolve("EURUSD")?.providerSymbol, "EURUSD=X")
        XCTAssertEqual(QuoteSymbolResolver.resolve("EUR/USD")?.providerSymbol, "EURUSD=X")
        XCTAssertEqual(QuoteSymbolResolver.resolve("US100")?.providerSymbol, "^NDX")
        XCTAssertEqual(QuoteSymbolResolver.resolve("SPX")?.providerSymbol, "^GSPC")
        XCTAssertEqual(QuoteSymbolResolver.resolve("AAPL")?.providerSymbol, "AAPL")
        XCTAssertEqual(QuoteSymbolResolver.resolve("AAPL")?.kind, .stock)
        XCTAssertEqual(QuoteSymbolResolver.resolve("BTCUSD")?.providerSymbol, "BTC-USD")
        XCTAssertNil(QuoteSymbolResolver.resolve("   "))
    }

    func test_request_encodesSymbolAndAsksForIntraday() throws {
        let provider = YahooQuoteProvider()
        let request = provider.request(for: QuoteSymbol(display: "NDX", providerSymbol: "^NDX", kind: .index))
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(url.hasPrefix("https://query1.finance.yahoo.com/v8/finance/chart/%5ENDX?"), url)
        XCTAssertTrue(url.contains("interval=5m"))
        XCTAssertTrue(url.contains("range=1d"))
        let future = provider.request(for: QuoteSymbol(display: "MNQ", providerSymbol: "MNQ=F", kind: .future))
        XCTAssertTrue(future.url?.absoluteString.contains("/MNQ%3DF?") ?? false)
    }

    // MARK: - Parser

    private let mnq = QuoteSymbol(display: "MNQ", providerSymbol: "MNQ=F", kind: .future)

    private func chartJSON(price: Double = 20_150.5, previousClose: Double = 20_100, marketTime: Double,
                           periodStart: Double, periodEnd: Double, delay: Int? = 10) -> Data {
        let delayField = delay.map { "\"exchangeDataDelayedBy\": \($0)," } ?? ""
        return Data("""
        {"chart":{"result":[{"meta":{"currency":"USD","symbol":"MNQ=F","regularMarketPrice":\(price),
        "chartPreviousClose":\(previousClose),\(delayField)"regularMarketTime":\(Int(marketTime)),
        "currentTradingPeriod":{"regular":{"start":\(Int(periodStart)),"end":\(Int(periodEnd))}}},
        "timestamp":[\(Int(marketTime) - 600),\(Int(marketTime) - 300),\(Int(marketTime))],
        "indicators":{"quote":[{"close":[20100.25,null,\(price)]}]}}],"error":null}}
        """.utf8)
    }

    func test_parse_openMarket_changeSparklineAndDelay() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let data = chartJSON(marketTime: now.timeIntervalSince1970 - 600,
                             periodStart: now.timeIntervalSince1970 - 3_600, periodEnd: now.timeIntervalSince1970 + 3_600)
        let quote = try YahooQuoteProvider.parse(data, symbol: mnq, now: now)
        XCTAssertEqual(quote.price, 20_150.5)
        XCTAssertEqual(quote.change ?? 0, 50.5, accuracy: 1e-9)
        XCTAssertEqual(quote.changeFraction ?? 0, 50.5 / 20_100, accuracy: 1e-12)
        XCTAssertEqual(quote.points.count, 2, "null-koersen worden overgeslagen")
        XCTAssertTrue(quote.isMarketOpen)
        XCTAssertTrue(quote.isDelayed)
        XCTAssertEqual(quote.delayMinutes, 10)
        XCTAssertEqual(quote.lastUpdate, now.addingTimeInterval(-600))
    }

    func test_parse_outsideTradingPeriod_isClosed() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let data = chartJSON(marketTime: now.timeIntervalSince1970 - 90_000,
                             periodStart: now.timeIntervalSince1970 - 100_000, periodEnd: now.timeIntervalSince1970 - 86_400)
        XCTAssertFalse(try YahooQuoteProvider.parse(data, symbol: mnq, now: now).isMarketOpen)
    }

    func test_parse_insidePeriodButStale_isClosed() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let data = chartJSON(marketTime: now.timeIntervalSince1970 - 5 * 3_600,
                             periodStart: now.timeIntervalSince1970 - 6 * 3_600, periodEnd: now.timeIntervalSince1970 + 3_600, delay: 0)
        let quote = try YahooQuoteProvider.parse(data, symbol: QuoteSymbol(display: "AAPL", providerSymbol: "AAPL", kind: .stock), now: now)
        XCTAssertFalse(quote.isMarketOpen)
        XCTAssertFalse(quote.isDelayed)
    }

    func test_parse_errors() {
        let notFound = Data(#"{"chart":{"result":null,"error":{"code":"Not Found","description":"No data found"}}}"#.utf8)
        XCTAssertThrowsError(try YahooQuoteProvider.parse(notFound, symbol: mnq)) { error in
            XCTAssertEqual(error as? LiveQuoteError, .unknownSymbol("MNQ"))
        }
        XCTAssertThrowsError(try YahooQuoteProvider.parse(Data("<html>".utf8), symbol: mnq)) { error in
            XCTAssertEqual(error as? LiveQuoteError, .invalidResponse)
        }
    }

    // MARK: - Viewmodel

    private final class MockProvider: QuoteProviding, @unchecked Sendable {
        var results: [Result<LiveQuote, LiveQuoteError>]
        private(set) var requested: [String] = []
        var sourceName: String { "Test" }

        init(_ results: [Result<LiveQuote, LiveQuoteError>]) { self.results = results }

        func quote(for symbol: QuoteSymbol) async throws -> LiveQuote {
            requested.append(symbol.providerSymbol)
            let result = results.count > 1 ? results.removeFirst() : results[0]
            return try result.get()
        }
    }

    private func quote(_ symbol: QuoteSymbol, open: Bool) -> LiveQuote {
        LiveQuote(symbol: symbol, price: 100, previousClose: 99, currency: "USD", lastUpdate: Date(),
                  points: [], isMarketOpen: open, delayMinutes: 0)
    }

    private func settings() -> LiveQuoteSettings {
        LiveQuoteSettings(defaults: UserDefaults(suiteName: "LiveQuoteTests-\(UUID().uuidString)")!)
    }

    func test_symbol_followsMostRecentTrade_orOverride() {
        let old = Trade(symbol: "ESZ26", direction: .long, entryDate: Date(timeIntervalSince1970: 1_000), entryPrice: 1, quantity: 1)
        let recent = Trade(symbol: "MNQZ26", direction: .long, entryDate: Date(timeIntervalSince1970: 500),
                           exitDate: Date(timeIntervalSince1970: 2_000), entryPrice: 1, quantity: 1)
        XCTAssertEqual(LiveQuoteViewModel.symbol(for: [old, recent], override: nil)?.providerSymbol, "MNQ=F")
        XCTAssertEqual(LiveQuoteViewModel.symbol(for: [old, recent], override: "AAPL")?.providerSymbol, "AAPL")
        XCTAssertNil(LiveQuoteViewModel.symbol(for: [], override: nil))
    }

    func test_refresh_loadsAndKeepsLastQuoteOnError() async {
        let symbol = QuoteSymbol(display: "MNQ", providerSymbol: "MNQ=F", kind: .future)
        let provider = MockProvider([.success(quote(symbol, open: true)), .failure(.http(503))])
        let viewModel = LiveQuoteViewModel(provider: provider, settings: settings())
        viewModel.update(trades: [Trade(symbol: "MNQZ26", direction: .long, entryDate: Date(), entryPrice: 1, quantity: 1)])
        XCTAssertEqual(viewModel.symbol, symbol)

        await viewModel.refresh()
        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.quote?.price, 100)

        await viewModel.refresh()
        XCTAssertEqual(viewModel.phase, .failed(LiveQuoteError.http(503).errorDescription!))
        XCTAssertEqual(viewModel.quote?.price, 100, "oude koers blijft zichtbaar")
        XCTAssertEqual(provider.requested, ["MNQ=F", "MNQ=F"])
    }

    func test_pollInterval_dependsOnMarketState() {
        let symbol = QuoteSymbol(display: "AAPL", providerSymbol: "AAPL", kind: .stock)
        XCTAssertEqual(LiveQuoteViewModel.interval(after: .loaded, quote: quote(symbol, open: true)), LiveQuoteViewModel.openInterval)
        XCTAssertEqual(LiveQuoteViewModel.interval(after: .loaded, quote: quote(symbol, open: false)), LiveQuoteViewModel.closedInterval)
        XCTAssertEqual(LiveQuoteViewModel.interval(after: .failed("x"), quote: nil), LiveQuoteViewModel.errorInterval)
    }

    func test_startStop_respectsSettingsAndSymbol() {
        let symbol = QuoteSymbol(display: "AAPL", providerSymbol: "AAPL", kind: .stock)
        let settings = settings()
        let viewModel = LiveQuoteViewModel(provider: MockProvider([.success(quote(symbol, open: true))]), settings: settings)

        viewModel.start()
        XCTAssertFalse(viewModel.isPolling, "zonder symbool geen polling")

        viewModel.update(trades: [Trade(symbol: "AAPL", direction: .long, entryDate: Date(), entryPrice: 1, quantity: 1)])
        viewModel.start()
        XCTAssertTrue(viewModel.isPolling)
        viewModel.stop()
        XCTAssertFalse(viewModel.isPolling)

        settings.isEnabled = false
        viewModel.start()
        XCTAssertFalse(viewModel.isPolling, "uitgeschakeld → geen polling")
    }
}
