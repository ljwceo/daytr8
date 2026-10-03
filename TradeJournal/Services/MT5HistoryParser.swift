import Foundation
import CoreGraphics

/// Eén trade zoals de parser hem van een MT5-screenshot leest. Velden die
/// niet (betrouwbaar) gelezen zijn blijven `nil` — er wordt nooit gegokt.
public struct MT5ParsedTrade: Equatable, Sendable {

    public enum Field: String, CaseIterable, Hashable, Sendable {
        case symbol, direction, volume, entryPrice, exitPrice, closeTime, pnl

        public var displayName: String {
            switch self {
            case .symbol: return "Symbool"
            case .direction: return "Richting"
            case .volume: return "Volume"
            case .entryPrice: return "Entry"
            case .exitPrice: return "Exit"
            case .closeTime: return "Sluittijd"
            case .pnl: return "P&L"
            }
        }
    }

    public var symbol: String?
    public var direction: TradeDirection?
    public var volume: Double?
    public var entryPrice: Double?
    public var exitPrice: Double?
    public var closeTime: Date?
    public var pnl: Double?
    /// Velden met lage OCR-zekerheid, een OCR-correctie (bijv. "O" → "0")
    /// of een afwijkende plek op de screenshot.
    public var uncertainFields: Set<Field>
    /// De bovenste of onderste regel van de trade ontbreekt (afgekapt aan de
    /// rand van de screenshot, of niet gelezen).
    public var isTruncated: Bool
    /// De herkende tekst waar de trade uit komt (voor het controlescherm).
    public var sourceLines: [String]

    public init(
        symbol: String? = nil,
        direction: TradeDirection? = nil,
        volume: Double? = nil,
        entryPrice: Double? = nil,
        exitPrice: Double? = nil,
        closeTime: Date? = nil,
        pnl: Double? = nil,
        uncertainFields: Set<Field> = [],
        isTruncated: Bool = false,
        sourceLines: [String] = []
    ) {
        self.symbol = symbol
        self.direction = direction
        self.volume = volume
        self.entryPrice = entryPrice
        self.exitPrice = exitPrice
        self.closeTime = closeTime
        self.pnl = pnl
        self.uncertainFields = uncertainFields
        self.isTruncated = isTruncated
        self.sourceLines = sourceLines
    }

    public func hasValue(_ field: Field) -> Bool {
        switch field {
        case .symbol: return !(symbol ?? "").isEmpty
        case .direction: return direction != nil
        case .volume: return volume != nil
        case .entryPrice: return entryPrice != nil
        case .exitPrice: return exitPrice != nil
        case .closeTime: return closeTime != nil
        case .pnl: return pnl != nil
        }
    }

    public var missingFields: [Field] { Field.allCases.filter { !hasValue($0) } }
    public var isComplete: Bool { missingFields.isEmpty }
}

/// Leest de geschiedenis (History-tab) van de MetaTrader 5-app voor iOS uit
/// door Vision herkende tekstblokken mét positie.
///
/// Formaat per trade (twee regels):
/// ```
/// AUDCAD sell 0.50                      -1 270.65
/// 0.89123 → 0.89050             2026.04.24 17:58:32
/// ```
/// - Richting komt uit het woord `buy`/`sell` (nooit uit de kleur).
/// - Bedragen: spatie (ook non-breaking/smalle spatie) als duizendtal-
///   scheiding, punt als decimaalteken, min-teken ook als `−`/`–`.
/// - Prijzen: gewone decimalen (XAUUSD `2345.67`, forex `0.89123`).
/// - Sluittijd: `YYYY.MM.DD HH:MM:SS` in `timeZone`.
///
/// Blokken worden per soort herkend (kop, prijzen, tijd, bedrag) en op
/// hoogte aan een trade gekoppeld; zo maakt het niet uit of Vision de P&L
/// of de datum als los blok of samen met de regel levert, en lopen regels
/// die net niet op één lijn liggen niet door elkaar. Een trade waarvan een
/// regel ontbreekt (afgekapt aan de rand) komt mee als onvolledig, met de
/// ontbrekende velden leeg.
public struct MT5HistoryParser: Sendable {

    /// Vision-zekerheid waaronder een veld als onzeker gemarkeerd wordt.
    public static let lowConfidenceThreshold: Float = 0.5

    public var timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    // MARK: - Fragmenten

    private struct Geometry {
        let midY: CGFloat
        let minX: CGFloat
        let maxX: CGFloat
        let height: CGFloat
        let lowConfidence: Bool
        let text: String
    }

    private struct HeaderFragment {
        let geometry: Geometry
        let symbol: String
        let direction: TradeDirection
        let volume: Double?
        let volumeUncertain: Bool
        let mergedPnL: Double?
        let mergedPnLUncertain: Bool
    }

    private struct PriceFragment {
        let geometry: Geometry
        let entry: Double?
        let exit: Double?
        let uncertain: Bool
    }

    private struct DateFragment {
        let geometry: Geometry
        let date: Date
    }

    private struct AmountFragment {
        let geometry: Geometry
        let value: Double
        let uncertain: Bool
    }

    private struct Fragments {
        var headers: [HeaderFragment] = []
        var prices: [PriceFragment] = []
        var dates: [DateFragment] = []
        var amounts: [AmountFragment] = []
    }

    // MARK: - Parsen

    /// Tekstregels zonder posities (fixtures, tests): elke regel wordt één
    /// blok over de volle breedte.
    public func parse(lines: [String]) -> [MT5ParsedTrade] {
        parse(ScreenshotLineBuilder.boxes(fromLines: lines))
    }

    /// Alle trades op één screenshot, van boven naar beneden.
    public func parse(_ boxes: [RecognizedTextBox]) -> [MT5ParsedTrade] {
        let usable = boxes.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usable.isEmpty else { return [] }

        var fragments = Fragments()
        for box in Self.mergingSplitHeaders(usable) { classify(box, into: &fragments) }

        let unit = Self.median(usable.map { $0.boundingBox.height }) ?? 0.02
        let headers = fragments.headers.sorted { $0.geometry.midY > $1.geometry.midY }

        /// Index van de kop waar iets op hoogte `y` bij hoort: de laatste kop
        /// (van boven) die niet duidelijk lager staat. `nil` = boven de eerste kop.
        func owner(_ y: CGFloat) -> Int? {
            var result: Int?
            for (index, header) in headers.enumerated() {
                if y <= header.geometry.midY + unit * 0.6 { result = index } else { break }
            }
            return result
        }

        var trades: [MT5ParsedTrade] = []

        // Boven de eerste kop: de onderste regel van een afgekapte trade.
        let orphanPrices = fragments.prices.filter { owner($0.geometry.midY) == nil }
        for price in orphanPrices.sorted(by: { $0.geometry.midY > $1.geometry.midY }) {
            var trade = MT5ParsedTrade(entryPrice: price.entry, exitPrice: price.exit, isTruncated: true, sourceLines: [price.geometry.text])
            if price.uncertain { trade.uncertainFields.formUnion([.entryPrice, .exitPrice]) }
            if let date = fragments.dates
                .filter({ owner($0.geometry.midY) == nil && abs($0.geometry.midY - price.geometry.midY) <= unit * 0.6 })
                .min(by: { abs($0.geometry.midY - price.geometry.midY) < abs($1.geometry.midY - price.geometry.midY) }) {
                trade.closeTime = date.date
                if date.geometry.lowConfidence { trade.uncertainFields.insert(.closeTime) }
                if date.geometry.text != price.geometry.text { trade.sourceLines.append(date.geometry.text) }
            }
            trades.append(trade)
        }

        for (index, header) in headers.enumerated() {
            trades.append(assemble(header, index: index, owner: owner, fragments: fragments, unit: unit))
        }
        return trades
    }

    private func assemble(_ header: HeaderFragment, index: Int, owner: (CGFloat) -> Int?, fragments: Fragments, unit: CGFloat) -> MT5ParsedTrade {
        let headerY = header.geometry.midY
        let maxBelow = unit * 2.8

        var trade = MT5ParsedTrade(symbol: header.symbol, direction: header.direction, volume: header.volume, sourceLines: [header.geometry.text])
        if header.geometry.lowConfidence { trade.uncertainFields.formUnion([.symbol, .direction]) }
        if header.volumeUncertain || header.geometry.lowConfidence { trade.uncertainFields.insert(.volume) }

        // Prijsregel: de dichtstbijzijnde onder de kop.
        let price = fragments.prices
            .filter { owner($0.geometry.midY) == index && $0.geometry.midY < headerY - unit * 0.3 && headerY - $0.geometry.midY <= maxBelow }
            .max { $0.geometry.midY < $1.geometry.midY }
        if let price {
            trade.entryPrice = price.entry
            trade.exitPrice = price.exit
            if price.uncertain || price.geometry.lowConfidence { trade.uncertainFields.formUnion([.entryPrice, .exitPrice]) }
            if price.geometry.text != header.geometry.text { trade.sourceLines.append(price.geometry.text) }
        }

        // Sluittijd: op de prijsregel, anders de dichtstbijzijnde onder de kop.
        let anchorY = price?.geometry.midY ?? headerY - unit * 1.3
        let date = fragments.dates
            .filter { owner($0.geometry.midY) == index && $0.geometry.midY < headerY - unit * 0.3 && headerY - $0.geometry.midY <= maxBelow }
            .min { abs($0.geometry.midY - anchorY) < abs($1.geometry.midY - anchorY) }
        if let date {
            trade.closeTime = date.date
            if date.geometry.lowConfidence { trade.uncertainFields.insert(.closeTime) }
            if price.map({ abs(date.geometry.midY - $0.geometry.midY) > unit * 0.6 }) ?? true { trade.uncertainFields.insert(.closeTime) }
            if !trade.sourceLines.contains(date.geometry.text) { trade.sourceLines.append(date.geometry.text) }
        }

        // P&L: rechts op de kopregel (dichter bij de kop dan bij de prijsregel).
        let splitY = price.map { (headerY + $0.geometry.midY) / 2 } ?? headerY - unit * 0.7
        let pnl = fragments.amounts
            .filter { owner($0.geometry.midY) == index && $0.geometry.midY > splitY && $0.geometry.minX >= header.geometry.minX }
            .max { $0.geometry.minX < $1.geometry.minX }
        if let pnl {
            trade.pnl = pnl.value
            if pnl.uncertain || pnl.geometry.lowConfidence { trade.uncertainFields.insert(.pnl) }
            if let merged = header.mergedPnL, abs(merged - pnl.value) > 0.005 { trade.uncertainFields.insert(.pnl) }
            if pnl.geometry.text != header.geometry.text { trade.sourceLines.insert(pnl.geometry.text, at: 1) }
        } else if let merged = header.mergedPnL {
            trade.pnl = merged
            if header.mergedPnLUncertain || header.geometry.lowConfidence { trade.uncertainFields.insert(.pnl) }
        } else if let price, let onPriceRow = fragments.amounts
            .filter({ owner($0.geometry.midY) == index && abs($0.geometry.midY - price.geometry.midY) <= unit * 0.6 })
            .max(by: { $0.geometry.minX < $1.geometry.minX }) {
            // Opengeklapte trade: P&L staat op de prijsregel. Wel overnemen,
            // maar laten controleren.
            trade.pnl = onPriceRow.value
            trade.uncertainFields.insert(.pnl)
        }

        trade.isTruncated = price == nil || date == nil
        return trade
    }

    // MARK: - Blokken herkennen

    private func classify(_ box: RecognizedTextBox, into fragments: inout Fragments) {
        let text = Self.unifySpaces(box.text).trimmingCharacters(in: .whitespacesAndNewlines)
        let geometry = Geometry(
            midY: box.boundingBox.midY,
            minX: box.boundingBox.minX,
            maxX: box.boundingBox.maxX,
            height: box.boundingBox.height,
            lowConfidence: box.confidence < Self.lowConfidenceThreshold,
            text: text
        )
        var rest = text

        // 1. Kopregel: symbool, buy/sell en volume (eventueel met P&L erachter).
        if let match = Self.firstMatch(Self.headerPattern, in: rest) {
            let symbol = match[1].uppercased()
            let direction: TradeDirection = match[2].lowercased() == "buy" ? .long : .short
            let volume = Self.parseVolume(match[3])
            var remainder = match.after
            if let dateMatch = Self.firstMatch(Self.dateTimePattern, in: remainder), let date = dateTime(from: dateMatch) {
                fragments.dates.append(DateFragment(geometry: geometry, date: date))
                remainder = dateMatch.before + " " + dateMatch.after
            }
            let amount = Self.parseAmount(remainder)
            fragments.headers.append(HeaderFragment(
                geometry: geometry,
                symbol: symbol,
                direction: direction,
                volume: volume?.value,
                volumeUncertain: volume?.corrected ?? false,
                mergedPnL: amount?.value,
                mergedPnLUncertain: amount?.corrected ?? false
            ))
            return
        }

        // 2. Sluittijd (los of achter de prijzen). Staan er twee tijden
        //    ("open → sluit"), dan is de laatste de sluittijd.
        var lastDate: Date?
        while let match = Self.firstMatch(Self.dateTimePattern, in: rest) {
            if let date = dateTime(from: match) { lastDate = date }
            rest = (match.before + " " + match.after).trimmingCharacters(in: .whitespaces)
        }
        if let lastDate {
            fragments.dates.append(DateFragment(geometry: geometry, date: lastDate))
            // Alleen een pijl over (tussen twee tijden): niets meer te lezen.
            if ["→", "->", "➝", "-", ">"].contains(rest) { rest = "" }
        }

        // 3. Prijzen: "entry → exit" (pijl), of twee decimale getallen zonder pijl.
        if let match = Self.firstMatch(Self.pricePairPattern, in: rest) {
            let entry = Self.parsePrice(match[1])
            let exit = Self.parsePrice(match[2])
            fragments.prices.append(PriceFragment(
                geometry: geometry,
                entry: entry?.value,
                exit: exit?.value,
                uncertain: (entry?.corrected ?? false) || (exit?.corrected ?? false) || match[0].contains(" - ") || match[0].contains("–") || match[0].contains("—")
            ))
            rest = (match.before + " " + match.after).trimmingCharacters(in: .whitespaces)
        } else if let match = Self.firstMatch(Self.pricePairWithoutArrowPattern, in: rest) {
            let entry = Self.parsePrice(match[1])
            let exit = Self.parsePrice(match[2])
            fragments.prices.append(PriceFragment(geometry: geometry, entry: entry?.value, exit: exit?.value, uncertain: true))
            rest = ""
        }

        // 4. Wat overblijft: een los bedrag (P&L)?
        if !rest.isEmpty, let amount = Self.parseAmount(rest) {
            fragments.amounts.append(AmountFragment(geometry: geometry, value: amount.value, uncertain: amount.corrected))
        }
    }

    /// Vision levert het (vette) symbool en het (gekleurde) "sell 0.50" soms
    /// als twee blokken. Buren op dezelfde regel die samen pas een kopregel
    /// vormen, worden hier tot één blok samengevoegd (laagste zekerheid telt).
    static func mergingSplitHeaders(_ boxes: [RecognizedTextBox]) -> [RecognizedTextBox] {
        var result: [RecognizedTextBox] = []
        for row in ScreenshotLineBuilder.rows(from: boxes) {
            var index = 0
            while index < row.count {
                let current = row[index]
                if firstMatch(headerPattern, in: unifySpaces(current.text)) == nil {
                    var merged: RecognizedTextBox?
                    for length in 2...3 where index + length <= row.count {
                        let parts = Array(row[index..<(index + length)])
                        let text = parts.map(\.text).joined(separator: " ")
                        guard firstMatch(headerPattern, in: unifySpaces(text)) != nil else { continue }
                        let rect = parts.dropFirst().reduce(parts[0].boundingBox) { $0.union($1.boundingBox) }
                        merged = RecognizedTextBox(text: text, boundingBox: rect, confidence: parts.map(\.confidence).min() ?? 1)
                        index += length
                        break
                    }
                    if let merged {
                        result.append(merged)
                        continue
                    }
                }
                result.append(current)
                index += 1
            }
        }
        return result
    }

    // MARK: - Getallen (statisch en los testbaar)

    /// Bedrag zoals MT5 het toont: `-1 270.65`, `1 040.25`, `−12.30`, `0.00`.
    /// Spatie, non-breaking (U+00A0), smalle (U+202F) of dunne spatie als
    /// duizendtalscheiding; punt als decimaalteken. Een komma telt alleen als
    /// duizendtalscheiding bij correcte groepen van drie én een decimaalpunt;
    /// "1270,65" (komma als decimaal) wordt niet gegokt maar geweigerd.
    /// - Returns: de waarde en of er een OCR-correctie nodig was (O → 0, l → 1).
    public static func parseAmount(_ raw: String) -> (value: Double, corrected: Bool)? {
        let unified = unifySpaces(raw).trimmingCharacters(in: .whitespaces)
        guard !unified.isEmpty else { return nil }
        var text = unified
        var negative = false
        if let first = text.first, "-−–—".contains(first) {
            negative = true
            text.removeFirst()
        } else if text.first == "+" {
            text.removeFirst()
        }
        text = text.trimmingCharacters(in: .whitespaces)
        let (digits, corrected) = correctedDigits(text)
        guard let digits else { return nil }

        let spaced = #"^\d{1,3}(?: \d{3})+(?:\.\d+)?$"#
        let plain = #"^\d+(?:\.\d+)?$"#
        let commaGrouped = #"^\d{1,3}(?:,\d{3})+\.\d+$"#
        guard matches(spaced, digits) || matches(plain, digits) || matches(commaGrouped, digits) else { return nil }
        let cleaned = digits.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "")
        guard let value = Double(cleaned) else { return nil }
        return (negative ? -value : value, corrected)
    }

    /// Prijs: `27173.35`, `2345.67`, `0.89123`, `151.234` (geen scheidingstekens).
    public static func parsePrice(_ raw: String) -> (value: Double, corrected: Bool)? {
        let (digits, corrected) = correctedDigits(unifySpaces(raw).trimmingCharacters(in: .whitespaces))
        guard let digits, matches(#"^\d+(?:\.\d+)?$"#, digits), let value = Double(digits), value > 0 else { return nil }
        return (value, corrected)
    }

    /// Volume/lots: `0.01`, `0.5`, `2.5`, `10`. Een komma wordt niet gegokt.
    public static func parseVolume(_ raw: String) -> (value: Double, corrected: Bool)? {
        let (digits, corrected) = correctedDigits(raw.trimmingCharacters(in: .whitespaces))
        guard let digits, matches(#"^\d+(?:\.\d+)?$"#, digits), let value = Double(digits), value > 0 else { return nil }
        return (value, corrected)
    }

    /// `YYYY.MM.DD HH:MM:SS` (ook `-` of `/` als scheiding, seconden optioneel).
    /// Ongeldige datums (13e maand, 31 april) → `nil`.
    public func parseDateTime(_ raw: String) -> Date? {
        guard let match = Self.firstMatch(Self.dateTimePattern, in: raw) else { return nil }
        return dateTime(from: match)
    }

    private func dateTime(from match: Match) -> Date? {
        guard let year = Int(match[1]), let month = Int(match[2]), let day = Int(match[3]),
              let hour = Int(match[4]), let minute = Int(match[5]) else { return nil }
        let second = Int(match[6]) ?? 0
        guard (2000...2100).contains(year), (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(calendar: calendar, timeZone: timeZone, year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }

    // MARK: - Tekst-helpers

    /// Alle soorten spaties (non-breaking, smal, dun, figuur) → gewone spatie.
    static func unifySpaces(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "\u{00A0}", "\u{202F}", "\u{2009}", "\u{2007}", "\u{2002}", "\u{2003}", "\t": result.append(" ")
            default: result.append(character)
            }
        }
        return result
    }

    /// Vervangt OCR-verwisselingen in een getal (O/o → 0, l/I/| → 1). Alleen
    /// als het token minstens één echt cijfer heeft en verder alleen uit
    /// cijfers, scheidingstekens en die letters bestaat.
    static func correctedDigits(_ text: String) -> (String?, Bool) {
        guard text.contains(where: \.isNumber) else { return (nil, false) }
        var corrected = false
        var result = ""
        for character in text {
            switch character {
            case "0"..."9", ".", ",", " ":
                result.append(character)
            case "O", "o":
                result.append("0")
                corrected = true
            case "l", "I", "|":
                result.append("1")
                corrected = true
            default:
                return (nil, false)
            }
        }
        return (result, corrected)
    }

    // MARK: - Regex

    /// Symbool (3–16 tekens, ook met suffix zoals `.r` of `#`), buy/sell en volume.
    static let headerPattern = #"(?:^|\s)([A-Za-z][A-Za-z0-9._#+\-]{2,15}?)\s*,?\s+(buy|sell)\b(?:\s+(?:limit|stop))?\s+([0-9OoIl|][0-9OoIl|.,]*)"#
    static let dateTimePattern = #"(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})[ T]+(\d{1,2}):(\d{2})(?::(\d{2}))?"#
    static let pricePairPattern = #"([0-9OoIl|]+(?:\.[0-9OoIl|]+)?)\s*(?:→|->|➝|➔|⟶|=>|>|\s[-–—]\s)\s*([0-9OoIl|]+(?:\.[0-9OoIl|]+)?)"#
    static let pricePairWithoutArrowPattern = #"^\s*(\d+\.\d+)\s+(\d+\.\d+)\s*$"#

    /// Eén regex-match met groepen en de tekst ervoor/erna.
    struct Match {
        let groups: [String]
        let before: String
        let after: String

        subscript(index: Int) -> String { index < groups.count ? groups[index] : "" }
    }

    private static let regexCache = RegexCache()

    static func firstMatch(_ pattern: String, in text: String) -> Match? {
        guard let regex = regexCache.regex(pattern) else { return nil }
        let nsText = text as NSString
        guard let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else { return nil }
        var groups: [String] = []
        for index in 0..<result.numberOfRanges {
            let range = result.range(at: index)
            groups.append(range.location == NSNotFound ? "" : nsText.substring(with: range))
        }
        let before = nsText.substring(to: result.range.location)
        let after = nsText.substring(from: result.range.location + result.range.length)
        return Match(groups: groups, before: before, after: after)
    }

    static func matches(_ pattern: String, _ text: String) -> Bool {
        guard let regex = regexCache.regex(pattern) else { return false }
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    static func median(_ values: [CGFloat]) -> CGFloat? {
        let sorted = values.filter { $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return nil }
        return sorted[sorted.count / 2]
    }
}

/// Thread-veilige cache van gecompileerde regexen.
private final class RegexCache: @unchecked Sendable {
    private var cache: [String: NSRegularExpression] = [:]
    private let lock = NSLock()

    func regex(_ pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[pattern] { return cached }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        cache[pattern] = regex
        return regex
    }
}
