import Foundation

/// Haalt tradevelden uit de OCR-tekst van een broker-screenshot (SPEC.md §12).
///
/// Werkt puur op tekst: `VisionTextRecognizer` levert de regels, deze parser
/// doet de rest. Zo is alles met tekstfixtures te testen, zonder afbeeldingen.
///
/// Werkwijze:
/// 1. Het platform herkennen aan de `keywords` van de broker-templates.
/// 2. Per veld de regexen van dat template toepassen; alle treffers worden
///    kandidaten (eerste = voorstel, rest = alternatieven).
/// 3. Ontbrekende velden aanvullen met het generieke terugvaltemplate
///    (`default.json`), behalve velden uit een groep die het platform-template
///    zelf al definieert (zie `ScreenshotField.relatedGroups`).
/// 4. Heuristieken: symbool zoeken tussen bekende instrumenten, koop-/
///    verkoopkant omzetten naar richting + entry/exit.
public struct ScreenshotParser: Sendable {

    /// Maximaal aantal kandidaten per veld (voorstel + alternatieven).
    public static let maxCandidates = 5

    public let templates: [ScreenshotTemplate]
    /// Symbolen met bekende tick size/value (presets + eigen instrumenten).
    public let knownSymbols: Set<String>
    /// Tijdzone voor tijden zonder offset (screenshots tonen lokale tijd).
    public let timeZone: TimeZone

    public init(
        templates: [ScreenshotTemplate],
        knownSymbols: Set<String> = Set(InstrumentPresets.all.map(\.symbol)),
        timeZone: TimeZone = .current
    ) {
        self.templates = templates
        self.knownSymbols = Set(knownSymbols.map { $0.uppercased() })
        self.timeZone = timeZone
    }

    // MARK: - Platform herkennen

    /// Het platform-template met de meeste keyword-treffers (bij gelijkspel de
    /// hoogste `priority`), of `nil` als geen enkel keyword voorkomt.
    public func detectBroker(in text: String) -> ScreenshotTemplate? {
        let haystack = Self.normalize(text).lowercased()
        var best: (hits: Int, priority: Int, template: ScreenshotTemplate)?
        for template in templates where !template.isFallbackTemplate {
            let hits = template.keywords.filter { !$0.isEmpty && haystack.contains($0.lowercased()) }.count
            guard hits > 0 else { continue }
            let priority = template.priority ?? 0
            if let current = best, (current.hits, current.priority) >= (hits, priority) { continue }
            best = (hits, priority, template)
        }
        return best?.template
    }

    // MARK: - Parsen

    /// Parseert OCR-regels (bovenaan eerst).
    public func parse(lines: [String], referenceDate: Date = Date()) -> ScreenshotParseResult {
        parse(lines.joined(separator: "\n"), referenceDate: referenceDate)
    }

    /// Parseert de volledige OCR-tekst.
    /// - Parameter referenceDate: dag voor tijden zonder datum (bijv. "09:31:22").
    public func parse(_ rawText: String, referenceDate: Date = Date()) -> ScreenshotParseResult {
        let text = Self.normalize(rawText)
        let broker = detectBroker(in: text)
        let fallbacks = templates.filter(\.isFallbackTemplate)

        var collected: [ScreenshotField: Collected] = [:]
        for field in ScreenshotField.allCases {
            if let broker, let values = candidates(for: field, template: broker, in: text, referenceDate: referenceDate) {
                collected[field] = Collected(values: values, source: broker.name, isFallback: false)
                continue
            }
            // Het platform-template is leidend voor de velden uit zijn groepen.
            if let broker, !field.relatedFields.isDisjoint(with: broker.definedFields) { continue }
            for fallback in fallbacks {
                if let values = candidates(for: field, template: fallback, in: text, referenceDate: referenceDate) {
                    collected[field] = Collected(values: values, source: fallback.name, isFallback: true)
                    break
                }
            }
        }

        if collected[.symbol] == nil, let found = symbolHeuristic(in: text) {
            collected[.symbol] = Collected(values: found, source: fallbacks.first?.name ?? "Generiek", isFallback: true)
        }

        var result = ScreenshotParseResult(templateID: broker?.id, templateName: broker?.name)
        result.symbol = Self.field(collected[.symbol]) { if case .text(let v) = $0 { return v }; return nil }
        result.direction = Self.field(collected[.direction]) { if case .direction(let v) = $0 { return v }; return nil }
        result.entryPrice = Self.numberField(collected[.entryPrice])
        result.exitPrice = Self.numberField(collected[.exitPrice])
        result.stopLoss = Self.numberField(collected[.stopLoss])
        result.takeProfit = Self.numberField(collected[.takeProfit])
        result.quantity = Self.numberField(collected[.quantity])
        result.grossPnL = Self.numberField(collected[.grossPnL])
        result.netPnL = Self.numberField(collected[.netPnL])
        result.commission = Self.numberField(collected[.commission])
        result.fees = Self.numberField(collected[.fees])
        result.entryTime = Self.dateField(collected[.entryTime])
        result.exitTime = Self.dateField(collected[.exitTime])

        resolveBuySellLegs(into: &result, collected: collected)
        return result
    }

    // MARK: - Koop-/verkoopkant

    /// Zet koop-/verkoopprijs en -tijd om naar richting + entry/exit.
    /// De eerste transactie in de tijd is de entry: eerst kopen = long.
    private func resolveBuySellLegs(into result: inout ScreenshotParseResult, collected: [ScreenshotField: Collected]) {
        let buyPrice = Self.numberField(collected[.buyPrice])
        let sellPrice = Self.numberField(collected[.sellPrice])
        let buyTime = Self.dateField(collected[.buyTime])
        let sellTime = Self.dateField(collected[.sellTime])

        // Richting uit de tijden gaat vóór een generieke gok, niet vóór wat
        // het platform-template zelf als richting leest.
        let directionIsGeneric = collected[.direction]?.isFallback ?? true
        if directionIsGeneric, let buy = buyTime?.value, let sell = sellTime?.value {
            result.direction = ParsedField(
                value: buy <= sell ? TradeDirection.long : TradeDirection.short,
                source: collected[.buyTime]?.source ?? "",
                isDerived: true
            )
        }

        guard buyPrice != nil || sellPrice != nil || buyTime != nil || sellTime != nil else { return }
        if result.direction == nil {
            // Zonder tijden of richting: de gangbare lezing (eerst gekocht).
            result.direction = ParsedField(value: TradeDirection.long, source: collected[.buyPrice]?.source ?? collected[.sellPrice]?.source ?? "", isDerived: true)
        }
        let isLong = result.direction?.value != .short
        if result.entryPrice == nil { result.entryPrice = isLong ? buyPrice : sellPrice }
        if result.exitPrice == nil { result.exitPrice = isLong ? sellPrice : buyPrice }
        if result.entryTime == nil { result.entryTime = isLong ? buyTime : sellTime }
        if result.exitTime == nil { result.exitTime = isLong ? sellTime : buyTime }
    }

    // MARK: - Symbool-heuristiek

    /// Zoekt woorden in hoofdletters die (na normalisatie, bijv. `MNQZ5` →
    /// `MNQ`) een bekend instrument zijn. Alleen hoofdletters, zodat gewone
    /// woorden als "es" of "si" niet als symbool gelezen worden.
    private func symbolHeuristic(in text: String) -> [CandidateValue]? {
        guard let regex = Self.regex(#"(?<![A-Za-z0-9])[A-Z0-9_/:!.]{2,20}(?![A-Za-z0-9])"#, caseInsensitive: false) else { return nil }
        var found: [CandidateValue] = []
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: nsRange) {
            guard let range = Range(match.range, in: text) else { continue }
            let token = String(text[range])
            guard token.contains(where: \.isLetter) else { continue }
            let symbol = ImportValueParser.normalizeSymbol(token, knownSymbols: knownSymbols)
            let candidate = CandidateValue.text(symbol)
            if knownSymbols.contains(symbol), !found.contains(candidate) {
                found.append(candidate)
            }
            if found.count == Self.maxCandidates { break }
        }
        return found.isEmpty ? nil : found
    }

    // MARK: - Kandidaten per veld

    private enum CandidateValue: Equatable {
        case text(String)
        case number(Double)
        case direction(TradeDirection)
        case date(Date)
    }

    private struct Collected {
        let values: [CandidateValue]
        let source: String
        let isFallback: Bool
    }

    /// Alle omgezette treffers van de regexen van `template` voor `field`,
    /// of `nil` als er geen enkele bruikbare treffer is.
    private func candidates(for field: ScreenshotField, template: ScreenshotTemplate, in text: String, referenceDate: Date) -> [CandidateValue]? {
        guard let rule = template.rule(for: field) else { return nil }
        let steps = Set((rule.postProcess ?? []).map { $0.lowercased() })
        let valueParser = ImportValueParser(dateOrder: template.dateOrder ?? .monthFirst, timeZone: timeZone)
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)

        var values: [CandidateValue] = []
        for pattern in rule.patterns {
            guard let regex = Self.regex(pattern, caseInsensitive: true) else { continue }
            for match in regex.matches(in: text, range: nsRange) {
                guard let raw = Self.captured(match, group: rule.group, in: text),
                      let value = convert(raw, field: field, steps: steps, valueParser: valueParser, referenceDate: referenceDate),
                      !values.contains(value) else { continue }
                values.append(value)
            }
        }

        if field == .symbol {
            // Bekende instrumenten eerst: die leveren tick size/value.
            let known = values.filter { if case .text(let s) = $0 { return knownSymbols.contains(s) }; return false }
            values = known + values.filter { !known.contains($0) }
        }
        return values.isEmpty ? nil : Array(values.prefix(Self.maxCandidates))
    }

    private func convert(_ raw: String, field: ScreenshotField, steps: Set<String>, valueParser: ImportValueParser, referenceDate: Date) -> CandidateValue? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if steps.contains("strip_spaces") { text.removeAll { $0.isWhitespace } }
        if steps.contains("uppercase") { text = text.uppercased() }
        guard !text.isEmpty else { return nil }

        switch field.valueKind {
        case .symbol:
            let symbol = ImportValueParser.normalizeSymbol(text, knownSymbols: knownSymbols)
            guard symbol.contains(where: \.isLetter), symbol.count <= 12 else { return nil }
            return .text(symbol)
        case .direction:
            return valueParser.direction(text).map { .direction($0) }
        case .number:
            guard var number = valueParser.number(text) else { return nil }
            if steps.contains("absolute") { number = abs(number) }
            if steps.contains("negate") { number = -number }
            // Prijzen en aantallen zijn altijd positief; een 0 is geen treffer.
            let mustBePositive: Set<ScreenshotField> = [.entryPrice, .exitPrice, .stopLoss, .takeProfit, .quantity, .buyPrice, .sellPrice]
            if mustBePositive.contains(field), number <= 0 { return nil }
            return .number(number)
        case .dateTime:
            if let date = valueParser.date(text) { return .date(date) }
            return timeOnly(text, on: referenceDate).map { .date($0) }
        }
    }

    /// "09:31:22", "9:31 AM" → die tijd op de dag van `referenceDate`.
    private func timeOnly(_ text: String, on referenceDate: Date) -> Date? {
        guard let regex = Self.regex(#"^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp][Mm])?$"#, caseInsensitive: false),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) else { return nil }
        func group(_ index: Int) -> String {
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
        var hour = Int(group(1)) ?? 0
        let minute = Int(group(2)) ?? 0
        let second = Int(group(3)) ?? 0
        let meridiem = group(4).uppercased()
        if meridiem == "PM" && hour < 12 { hour += 12 }
        if meridiem == "AM" && hour == 12 { hour = 0 }
        guard hour < 24, minute < 60, second < 60 else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)
    }

    // MARK: - Resultaat opbouwen

    private static func field<T: Equatable>(_ collected: Collected?, _ extract: (CandidateValue) -> T?) -> ParsedField<T>? {
        guard let collected else { return nil }
        let values = collected.values.compactMap(extract)
        guard let first = values.first else { return nil }
        return ParsedField(value: first, alternatives: Array(values.dropFirst()), source: collected.source)
    }

    private static func numberField(_ collected: Collected?) -> ParsedField<Double>? {
        field(collected) { if case .number(let v) = $0 { return v }; return nil }
    }

    private static func dateField(_ collected: Collected?) -> ParsedField<Date>? {
        field(collected) { if case .date(let v) = $0 { return v }; return nil }
    }

    // MARK: - Tekst & regex-helpers

    /// Maakt OCR-tekst uniform: typografische mintekens/streepjes naar "-",
    /// harde spaties naar gewone spaties, breedte-varianten van "$".
    static func normalize(_ text: String) -> String {
        var result = text
        for dash in ["\u{2212}", "\u{2013}", "\u{2014}", "\u{2012}"] {
            result = result.replacingOccurrences(of: dash, with: "-")
        }
        result = result.replacingOccurrences(of: "\u{00A0}", with: " ")
        result = result.replacingOccurrences(of: "\u{FF04}", with: "$")
        return result
    }

    /// Waarde uit een match: capture group `group` (1-based), anders de eerste
    /// niet-lege group, anders de hele match.
    private static func captured(_ match: NSTextCheckingResult, group: Int?, in text: String) -> String? {
        if let group {
            guard group < match.numberOfRanges, let range = Range(match.range(at: group), in: text) else { return nil }
            return String(text[range])
        }
        for index in stride(from: 1, to: match.numberOfRanges, by: 1) {
            if let range = Range(match.range(at: index), in: text), !range.isEmpty {
                return String(text[range])
            }
        }
        return Range(match.range, in: text).map { String(text[$0]) }
    }

    /// Regexen die niet compileren (zoals ICU ze leest). Handig om een nieuw
    /// template te controleren; de parser slaat zulke patronen over.
    public static func invalidPatterns(in template: ScreenshotTemplate) -> [String] {
        template.fields.values
            .flatMap(\.patterns)
            .filter { regex($0, caseInsensitive: true) == nil }
    }

    private static let cache = RegexCache()

    private static func regex(_ pattern: String, caseInsensitive: Bool) -> NSRegularExpression? {
        cache.regex(pattern, caseInsensitive: caseInsensitive)
    }
}

/// Thread-veilige cache voor gecompileerde regexen (templates worden bij elke
/// screenshot opnieuw toegepast).
private final class RegexCache: @unchecked Sendable {
    private var compiled: [String: NSRegularExpression] = [:]
    private var failed: Set<String> = []
    private let lock = NSLock()

    func regex(_ pattern: String, caseInsensitive: Bool) -> NSRegularExpression? {
        let key = (caseInsensitive ? "i:" : "s:") + pattern
        lock.lock()
        defer { lock.unlock() }
        if let cached = compiled[key] { return cached }
        if failed.contains(key) { return nil }
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            failed.insert(key)
            return nil
        }
        compiled[key] = regex
        return regex
    }
}
