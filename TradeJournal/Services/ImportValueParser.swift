import Foundation

/// Volgorde van dag en maand in datums als `05/12/2024` (ambigu).
/// Datums die met het jaar beginnen (`2024-12-05`) zijn altijd eenduidig.
public enum ImportDateOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case monthFirst = "month_first"
    case dayFirst = "day_first"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .monthFirst: return "MM/DD/JJJJ (VS)"
        case .dayFirst: return "DD/MM/JJJJ (EU)"
        }
    }
}

/// Koop- of verkoopkant van een fill.
public enum FillSide: String, Codable, Sendable {
    case buy
    case sell

    /// +1 voor koop, -1 voor verkoop.
    public var sign: Double { self == .buy ? 1 : -1 }
}

/// Zet ruwe CSV-strings om naar getallen, datums, richtingen en symbolen.
///
/// Broker-exports verschillen sterk in notatie (`$1,234.50`, `(50.00)`,
/// `1.234,50`, `12/05/2024 9:31:22 PM`, `2024.12.05 09:31`, `MNQZ4`,
/// `CME_MINI:NQ1!`, `NQ 12-24`, ...). Deze parser vangt die varianten op één
/// plek af, zodat `CSVImportService` alleen met schone waardes werkt.
public struct ImportValueParser {

    public var dateOrder: ImportDateOrder
    /// Tijdzone voor datums zonder expliciete offset.
    public var timeZone: TimeZone

    public init(dateOrder: ImportDateOrder = .monthFirst, timeZone: TimeZone = .current) {
        self.dateOrder = dateOrder
        self.timeZone = timeZone
    }

    // MARK: - Getallen

    /// Parseert een getal met optionele valutatekens, duizendtallen,
    /// haakjes-notatie voor negatief en komma of punt als decimaalteken.
    /// Geeft `nil` terug voor lege of onleesbare waardes.
    public func number(_ raw: String) -> Double? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Boekhoudnotatie: "(50.00)" of "$(50.00)" is negatief.
        var negative = text.contains("(") && text.hasSuffix(")")

        // Alles behalve cijfers, scheidingstekens en minteken weghalen
        // (valutatekens, spaties, "USD", "%", ...).
        text = String(text.unicodeScalars.filter { scalar in
            CharacterSet.decimalDigits.contains(scalar) || scalar == "." || scalar == "," || scalar == "-"
        }.map { Character($0) })

        if text.hasPrefix("-") {
            negative.toggle()
            text.removeFirst()
        }
        text.removeAll { $0 == "-" }
        guard !text.isEmpty, text.contains(where: \.isNumber) else { return nil }

        let lastDot = text.lastIndex(of: ".")
        let lastComma = text.lastIndex(of: ",")

        switch (lastDot, lastComma) {
        case let (dot?, comma?):
            // Beide aanwezig: het laatste teken is het decimaalteken.
            if dot > comma {
                text.removeAll { $0 == "," }
            } else {
                text.removeAll { $0 == "." }
                text = text.replacingOccurrences(of: ",", with: ".")
            }
        case (nil, _?):
            // Alleen komma's: één komma die niet exact 3 cijfers scheidt
            // (of met "0" ervoor) is een decimaalteken, anders duizendtallen.
            let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 2, parts[1].count != 3 || parts[0] == "0" || parts[0].isEmpty {
                text = text.replacingOccurrences(of: ",", with: ".")
            } else {
                text.removeAll { $0 == "," }
            }
        case (_?, nil):
            // Alleen punten: meerdere punten zijn duizendtallen (1.234.567).
            if text.filter({ $0 == "." }).count > 1 {
                text.removeAll { $0 == "." }
            }
        case (nil, nil):
            break
        }

        guard let value = Double(text) else { return nil }
        return negative ? -value : value
    }

    // MARK: - Datums

    /// Parseert een datum(+tijd). Ondersteunt jaar-eerst (`2024-12-05`,
    /// `2024.12.05`), maand/dag-eerst volgens `dateOrder`, 12- en 24-uurs tijd,
    /// fracties van seconden, ISO 8601 `T`-scheiding, offsets (`Z`, `+01:00`,
    /// `-0500`) en Unix-timestamps (seconden of milliseconden).
    public func date(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Unix timestamp.
        if text.allSatisfy(\.isNumber), let epoch = Double(text) {
            if text.count == 13 { return Date(timeIntervalSince1970: epoch / 1000) }
            if text.count == 10 { return Date(timeIntervalSince1970: epoch) }
        }

        guard let datePart = Self.firstMatch(Self.yearFirstPattern, in: text) ?? Self.firstMatch(Self.yearLastPattern, in: text) else {
            return nil
        }

        var year = 0
        var month = 0
        var day = 0
        if datePart.pattern == Self.yearFirstPattern {
            year = Int(datePart.groups[0]) ?? 0
            month = Int(datePart.groups[1]) ?? 0
            day = Int(datePart.groups[2]) ?? 0
        } else {
            let first = Int(datePart.groups[0]) ?? 0
            let second = Int(datePart.groups[1]) ?? 0
            year = Int(datePart.groups[2]) ?? 0
            switch dateOrder {
            case .monthFirst:
                month = first
                day = second
            case .dayFirst:
                day = first
                month = second
            }
            // Zelfcorrectie als de gekozen volgorde onmogelijk is (bijv. 25/12).
            if month > 12 && day <= 12 { swap(&month, &day) }
            if year < 100 { year += 2000 }
        }
        guard (1...12).contains(month), (1...31).contains(day), year > 1900 else { return nil }

        let remainder = String(text[datePart.range.upperBound...])
        var hour = 0
        var minute = 0
        var second = 0
        if let time = Self.firstMatch(Self.timePattern, in: remainder) {
            hour = Int(time.groups[0]) ?? 0
            minute = Int(time.groups[1]) ?? 0
            second = Int(time.groups[2]) ?? 0
            let meridiem = time.groups[4].uppercased()
            if meridiem == "PM" && hour < 12 { hour += 12 }
            if meridiem == "AM" && hour == 12 { hour = 0 }
        }

        var zone = timeZone
        if let offset = Self.firstMatch(Self.offsetPattern, in: remainder) {
            let token = offset.groups[0].uppercased()
            if token == "Z" || token == "UTC" || token == "GMT" {
                zone = TimeZone(secondsFromGMT: 0) ?? zone
            } else {
                let sign = token.hasPrefix("-") ? -1 : 1
                let digits = token.filter(\.isNumber)
                if digits.count == 4, let hh = Int(digits.prefix(2)), let mm = Int(digits.suffix(2)) {
                    zone = TimeZone(secondsFromGMT: sign * (hh * 3600 + mm * 60)) ?? zone
                }
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return calendar.date(from: components)
    }

    // MARK: - Richting / kant

    /// Herkent koop/verkoop in allerlei broker-notaties
    /// ("Buy", "B", "BOT", "Sell", "S", "SLD", "Long", "Short", "buy limit", ...).
    public func side(_ raw: String) -> FillSide? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if ["b", "bot", "bought", "buy", "long", "l"].contains(text) { return .buy }
        if ["s", "sld", "sold", "sell", "short", "sh"].contains(text) { return .sell }
        if text.contains("buy") || text.contains("long") { return .buy }
        if text.contains("sell") || text.contains("short") { return .sell }
        return nil
    }

    /// Richting van een complete trade ("Long", "Short", "Buy", "Sell").
    public func direction(_ raw: String) -> TradeDirection? {
        switch side(raw) {
        case .buy: return .long
        case .sell: return .short
        case nil: return nil
        }
    }

    // MARK: - Symbolen

    /// Normaliseert een broker-symbool naar het root-symbool van een bekend
    /// instrument, zodat tick size/value uit de presets gebruikt kunnen worden:
    /// - exchange-prefix weg (`CME_MINI:NQ1!` → `NQ`)
    /// - leading slash weg (`/MNQ` → `MNQ`)
    /// - NinjaTrader-expiratie weg (`NQ 12-24` → `NQ`)
    /// - future-maandcode + jaar weg (`MNQZ4`, `MNQZ24`, `MNQZ2024` → `MNQ`)
    /// - forex-suffixen weg (`EURUSD.a`, `EURUSDm`, `EUR/USD` → `EURUSD`)
    ///
    /// Onbekende symbolen worden alleen opgeschoond (hoofdletters, prefix weg).
    public static func normalizeSymbol(_ raw: String, knownSymbols: Set<String>) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let colon = text.lastIndex(of: ":") {
            text = String(text[text.index(after: colon)...])
        }
        while text.hasPrefix("/") { text.removeFirst() }
        if let firstToken = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).first {
            text = String(firstToken)
        }
        text = text.replacingOccurrences(of: "!", with: "")
        guard !text.isEmpty else { return text }

        let known = Set(knownSymbols.map { $0.uppercased() })
        if known.contains(text) { return text }

        // Continuous contract "NQ1" → "NQ".
        let withoutTrailingDigits = String(text.reversed().drop(while: \.isNumber).reversed())
        if known.contains(withoutTrailingDigits), withoutTrailingDigits.count < text.count,
           text.count - withoutTrailingDigits.count <= 2 {
            return withoutTrailingDigits
        }

        // Future-contract met maandcode + 1, 2 of 4 cijfers.
        if let match = firstMatch(futureContractPattern, in: text), known.contains(match.groups[0]) {
            return match.groups[0]
        }

        // Forex: "EUR/USD", "EURUSD.a", "EURUSDm", "EURUSD-ECN".
        let lettersOnly = text.filter { $0.isLetter }
        if lettersOnly.count >= 6 {
            let pair = String(lettersOnly.prefix(6))
            if known.contains(pair) { return pair }
        }

        return text
    }

    // MARK: - Regex-helpers

    private static let yearFirstPattern = #"(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})"#
    private static let yearLastPattern = #"(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})"#
    private static let timePattern = #"(\d{1,2}):(\d{2})(?::(\d{2}))?(?:[.,](\d+))?\s*([AaPp][Mm])?"#
    private static let offsetPattern = #"(Z|UTC|GMT|[+-]\d{2}:?\d{2})\s*$"#
    private static let futureContractPattern = #"^([A-Z0-9]{1,4}?)[FGHJKMNQUVXZ](\d{1,2}|\d{4})$"#

    private struct Match {
        let pattern: String
        let range: Range<String.Index>
        /// Alle capture groups; niet-gematchte groepen zijn een lege string.
        let groups: [String]
    }

    private static var regexCache: [String: NSRegularExpression] = [:]
    private static let regexLock = NSLock()

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        regexLock.lock()
        defer { regexLock.unlock() }
        if let cached = regexCache[pattern] { return cached }
        let compiled = try? NSRegularExpression(pattern: pattern)
        regexCache[pattern] = compiled
        return compiled
    }

    private static func firstMatch(_ pattern: String, in text: String) -> Match? {
        guard let regex = regex(pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let result = regex.firstMatch(in: text, range: nsRange),
              let range = Range(result.range, in: text) else { return nil }
        var groups: [String] = []
        for index in 1..<result.numberOfRanges {
            if let groupRange = Range(result.range(at: index), in: text) {
                groups.append(String(text[groupRange]))
            } else {
                groups.append("")
            }
        }
        return Match(pattern: pattern, range: range, groups: groups)
    }
}
