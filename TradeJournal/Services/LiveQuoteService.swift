import Foundation

/// Een bron van live (of licht vertraagde) koersen.
public protocol QuoteProviding: Sendable {
    /// Naam voor in de UI ("Yahoo Finance").
    var sourceName: String { get }
    func quote(for symbol: QuoteSymbol) async throws -> LiveQuote
}

public enum LiveQuoteError: Error, Equatable, LocalizedError {
    case unknownSymbol(String)
    case noData
    case http(Int)
    case invalidResponse
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .unknownSymbol(let symbol): return "Geen koers gevonden voor \(symbol)."
        case .noData: return "De koersbron gaf geen koers terug."
        case .http(let status): return "De koersbron is niet bereikbaar (HTTP \(status))."
        case .invalidResponse: return "De koersbron gaf een onleesbaar antwoord."
        case .network(let detail): return "Geen verbinding met de koersbron: \(detail)"
        }
    }
}

/// Koersen via de (onofficiële, gratis) chart-API van Yahoo Finance.
///
/// - Geen API-key nodig. De basis-URL is te overschrijven met de Info.plist-
///   sleutel `LiveQuoteBaseURL` (config, niet in code), bijv. voor een proxy.
/// - CME-futures zijn ~10 minuten vertraagd; aandelen en indexen meestal
///   realtime tot 15 minuten. De vertraging komt uit `exchangeDataDelayedBy`
///   en wordt in de UI getoond.
/// - Onofficieel: Yahoo kan de API zonder aankondiging wijzigen. De kaart
///   toont dan een foutstatus; de rest van de app werkt gewoon offline door.
public struct YahooQuoteProvider: QuoteProviding {

    public static let defaultBaseURL = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/")!
    /// Info.plist-sleutel om de basis-URL te overschrijven.
    public static let baseURLInfoKey = "LiveQuoteBaseURL"

    public var sourceName: String { "Yahoo Finance" }

    private let session: URLSession
    private let baseURL: URL

    public init(session: URLSession = .shared, baseURL: URL? = nil, bundle: Bundle = .main) {
        self.session = session
        let configured = (bundle.object(forInfoDictionaryKey: Self.baseURLInfoKey) as? String).flatMap(URL.init(string:))
        self.baseURL = baseURL ?? configured ?? Self.defaultBaseURL
    }

    public func request(for symbol: QuoteSymbol) -> URLRequest {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._")
        let encoded = symbol.providerSymbol.addingPercentEncoding(withAllowedCharacters: allowed) ?? symbol.providerSymbol
        var base = baseURL.absoluteString
        if !base.hasSuffix("/") { base += "/" }
        var components = URLComponents(string: base + encoded)
        components?.queryItems = [
            URLQueryItem(name: "interval", value: "5m"),
            URLQueryItem(name: "range", value: "1d"),
            URLQueryItem(name: "includePrePost", value: "false")
        ]
        var request = URLRequest(url: components?.url ?? baseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public func quote(for symbol: QuoteSymbol) async throws -> LiveQuote {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request(for: symbol))
        } catch {
            throw LiveQuoteError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // Yahoo geeft 404 met een JSON-fout voor onbekende symbolen.
            if http.statusCode == 404 { throw LiveQuoteError.unknownSymbol(symbol.display) }
            throw LiveQuoteError.http(http.statusCode)
        }
        return try Self.parse(data, symbol: symbol)
    }

    // MARK: - Parsen (puur, getest)

    public static func parse(_ data: Data, symbol: QuoteSymbol, now: Date = Date()) throws -> LiveQuote {
        let decoded: ChartResponse
        do {
            decoded = try JSONDecoder().decode(ChartResponse.self, from: data)
        } catch {
            throw LiveQuoteError.invalidResponse
        }
        guard let result = decoded.chart.result?.first else {
            if decoded.chart.error != nil { throw LiveQuoteError.unknownSymbol(symbol.display) }
            throw LiveQuoteError.noData
        }
        let meta = result.meta

        let timestamps = result.timestamp ?? []
        let closes = result.indicators.quote?.first?.close ?? []
        var points: [QuotePoint] = []
        for (index, timestamp) in timestamps.enumerated() where index < closes.count {
            if let close = closes[index] {
                points.append(QuotePoint(date: Date(timeIntervalSince1970: timestamp), price: close))
            }
        }

        guard let price = meta.regularMarketPrice ?? points.last?.price else { throw LiveQuoteError.noData }
        let lastUpdate = meta.regularMarketTime.map { Date(timeIntervalSince1970: $0) } ?? points.last?.date ?? now

        let delay = meta.exchangeDataDelayedBy ?? (symbol.kind == .future ? 10 : 0)
        let isOpen: Bool = {
            guard let regular = meta.currentTradingPeriod?.regular else { return false }
            let seconds = now.timeIntervalSince1970
            guard seconds >= regular.start, seconds < regular.end else { return false }
            // Feestdag/handelsstop: binnen het venster maar al lang geen koers.
            return now.timeIntervalSince(lastUpdate) < 2 * 3600 + Double(delay) * 60
        }()

        return LiveQuote(
            symbol: symbol,
            price: price,
            previousClose: meta.previousClose ?? meta.chartPreviousClose,
            currency: meta.currency,
            lastUpdate: lastUpdate,
            points: points,
            isMarketOpen: isOpen,
            delayMinutes: max(delay, 0)
        )
    }

    // MARK: - JSON

    struct ChartResponse: Decodable {
        let chart: Chart

        struct Chart: Decodable {
            let result: [Result]?
            let error: APIError?
        }

        struct APIError: Decodable {
            let code: String?
            let description: String?
        }

        struct Result: Decodable {
            let meta: Meta
            let timestamp: [Double]?
            let indicators: Indicators
        }

        struct Meta: Decodable {
            let currency: String?
            let symbol: String?
            let regularMarketPrice: Double?
            let chartPreviousClose: Double?
            let previousClose: Double?
            let regularMarketTime: Double?
            let exchangeDataDelayedBy: Int?
            let currentTradingPeriod: TradingPeriods?
        }

        struct TradingPeriods: Decodable {
            let regular: Period?
        }

        struct Period: Decodable {
            let start: Double
            let end: Double
        }

        struct Indicators: Decodable {
            let quote: [QuoteSeries]?
        }

        struct QuoteSeries: Decodable {
            let close: [Double?]?
        }
    }
}
