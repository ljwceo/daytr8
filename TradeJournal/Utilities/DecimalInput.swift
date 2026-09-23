import Foundation

/// Parseren en formatteren van getallen die de gebruiker zelf intypt
/// (decimalPad). Accepteert zowel een komma als een punt als decimaalteken —
/// het Nederlandse toetsenbord geeft een komma — maar geen duizendtallen:
/// bij handmatige invoer is "18000,25" altijd 18000.25.
enum DecimalInput {

    /// `nil` bij lege of ongeldige invoer ("1,2,3", "abc"). Een losse
    /// komma/punt aan het eind ("18000,") is geldig tijdens het typen.
    static func parse(_ text: String) -> Double? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.removeAll { $0 == " " || $0 == "\u{00A0}" }
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, cleaned.filter({ $0 == "." }).count <= 1 else { return nil }
        if cleaned == "." || cleaned == "-" || cleaned == "-." { return nil }
        if cleaned.hasSuffix(".") { cleaned.removeLast() }
        if cleaned.hasPrefix(".") { cleaned = "0" + cleaned }
        if cleaned.hasPrefix("-.") { cleaned = "-0" + cleaned.dropFirst() }
        return Double(cleaned)
    }

    /// Weergave in het invoerveld: leeg voor 0, anders zonder duizendtallen en
    /// met het decimaalteken van `locale`.
    static func format(_ value: Double, locale: Locale = .current) -> String {
        guard value != 0, value.isFinite else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 10
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
