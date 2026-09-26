import Foundation

/// Vertaalt het symbool van een trade naar een symbool van de koersbron
/// (Yahoo Finance-notatie):
/// - futures (ook met contractmaand, `MNQZ26`, `/MNQ`, `NQ 12-26`) →
///   doorlopend contract `MNQ=F`;
/// - forex (`EURUSD`, `EUR/USD`) → `EURUSD=X`;
/// - indexen (`NDX`, `US100`, `SPX`, ...) → `^NDX`, `^GSPC`, ...;
/// - crypto (`BTCUSD`) → `BTC-USD`;
/// - de rest als aandeel (`AAPL`, `ASML.AS`).
public enum QuoteSymbolResolver {

    /// Gangbare CFD-/indexnamen → Yahoo-index.
    public static let indexAliases: [String: String] = [
        "NDX": "^NDX", "NAS100": "^NDX", "US100": "^NDX", "USTEC": "^NDX", "NQ100": "^NDX",
        "SPX": "^GSPC", "SPX500": "^GSPC", "US500": "^GSPC", "SP500": "^GSPC",
        "DJI": "^DJI", "US30": "^DJI", "DJ30": "^DJI",
        "RUT": "^RUT", "US2000": "^RUT",
        "VIX": "^VIX",
        "DAX": "^GDAXI", "GER40": "^GDAXI", "DE40": "^GDAXI",
        "AEX": "^AEX", "UK100": "^FTSE", "FTSE": "^FTSE"
    ]

    private static let cryptoBases: Set<String> = ["BTC", "ETH", "SOL", "XRP", "ADA", "DOGE", "LTC"]

    /// - Parameters:
    ///   - raw: symbool zoals op de trade.
    ///   - category: categorie van het gekoppelde instrument (als bekend).
    public static func resolve(_ raw: String, category: InstrumentCategory? = nil) -> QuoteSymbol? {
        let known = Set(InstrumentPresets.all.map(\.symbol))
        var root = ImportValueParser.normalizeSymbol(raw, knownSymbols: known)
        if root.hasPrefix("^") { root.removeFirst() }
        guard !root.isEmpty else { return nil }

        if let index = indexAliases[root] {
            return QuoteSymbol(display: root, providerSymbol: index, kind: .index)
        }

        let presetCategory = InstrumentPresets.definition(for: root)?.category
        switch presetCategory ?? category {
        case .future?, .microFuture?:
            let contract = presetCategory == nil ? stripContractMonth(root) : root
            return QuoteSymbol(display: contract, providerSymbol: "\(contract)=F", kind: .future)
        case .forex?:
            let pair = String(root.filter(\.isLetter).prefix(6))
            guard pair.count == 6 else { break }
            return QuoteSymbol(display: pair, providerSymbol: "\(pair)=X", kind: .forex)
        case .crypto?:
            return crypto(root) ?? QuoteSymbol(display: root, providerSymbol: root, kind: .crypto)
        default:
            break
        }

        if let crypto = crypto(root) { return crypto }
        return QuoteSymbol(display: root, providerSymbol: root, kind: .stock)
    }

    /// `6EZ26` → `6E`, `ZNH7` → `ZN`. Laat symbolen zonder contractmaand staan.
    static func stripContractMonth(_ symbol: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"^([A-Z0-9]{1,4}?)[FGHJKMNQUVXZ](\d{1,2}|\d{4})$"#),
              let match = regex.firstMatch(in: symbol, range: NSRange(symbol.startIndex..., in: symbol)),
              let range = Range(match.range(at: 1), in: symbol) else {
            return symbol
        }
        return String(symbol[range])
    }

    private static func crypto(_ root: String) -> QuoteSymbol? {
        let letters = root.filter(\.isLetter)
        for base in cryptoBases where letters.hasPrefix(base) {
            let quote = letters.dropFirst(base.count)
            guard quote == "USD" || quote == "USDT" || quote.isEmpty else { continue }
            return QuoteSymbol(display: "\(base)USD", providerSymbol: "\(base)-USD", kind: .crypto)
        }
        return nil
    }
}
