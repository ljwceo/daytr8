import Foundation
import CoreGraphics

/// Leest tabellen uit Vision-blokken: een regel met kolomkoppen (bijv.
/// "Symbol  Qty  Buy Price  Sell Price  P&L") en per trade een rij eronder.
/// De waarden worden aan de kolom erboven gekoppeld via hun x-positie.
///
/// Welke koppen bij welk veld horen, staat in de `columns`-sectie van een
/// broker-template (`ScreenshotTemplate.ColumnRule`). Puur, zonder UI of
/// Vision, zodat het met tekstfixtures te testen is.
public enum ScreenshotTableReader {

    /// Minimaal aantal herkende koppen op één regel om als kopregel te tellen.
    public static let minimumHeaderColumns = 3

    /// Een gelezen tabel: het template waarvan de koppen herkend zijn en per
    /// datarij de ruwe tekst per kolomsleutel (`ScreenshotField.rawValue`).
    public struct Table: Equatable, Sendable {
        public let template: ScreenshotTemplate
        public let rows: [[String: String]]
    }

    /// Kolom uit de kopregel met zijn horizontale bereik.
    struct Column: Equatable {
        let key: String
        let minX: CGFloat
        let maxX: CGFloat
    }

    /// Eén woord uit een blok, met een geschatte x-positie (evenredig met de
    /// plek van de tekens in het blok). Woorden met maar één spatie ertussen
    /// horen bij dezelfde cel ("9/22/2025 9:31:22 AM"); twee of meer spaties
    /// (zoals `ScreenshotLineBuilder` blokken scheidt) beginnen een nieuwe.
    struct Token: Equatable {
        let text: String
        let minX: CGFloat
        let maxX: CGFloat
        let cell: Int
    }

    /// Zoekt de best herkende tabel. `preferred` (het platform dat aan de
    /// keywords herkend is) wint als zijn koppen herkend worden; anders het
    /// template met de meeste herkende koppen (bij gelijkspel hoogste `priority`).
    public static func read(
        _ boxes: [RecognizedTextBox],
        templates: [ScreenshotTemplate],
        preferred: ScreenshotTemplate? = nil
    ) -> Table? {
        let rows = ScreenshotLineBuilder.rows(from: boxes)
        guard rows.count >= 2 else { return nil }

        var best: (rank: (Int, Int, Int), template: ScreenshotTemplate, headerIndex: Int, columns: [Column])?
        for template in templates {
            guard let match = header(in: rows, template: template) else { continue }
            let rank = (template.id == preferred?.id ? 1 : 0, match.columns.count, template.priority ?? 0)
            if let current = best, current.rank >= rank { continue }
            best = (rank, template, match.index, match.columns)
        }
        guard let best else { return nil }

        let dataRows = rows[(best.headerIndex + 1)...].compactMap { row -> [String: String]? in
            let rowValues = values(in: row, columns: best.columns)
            let fieldCount = rowValues.keys.filter { ScreenshotField(rawValue: $0) != nil }.count
            return fieldCount >= 2 ? rowValues : nil
        }
        guard !dataRows.isEmpty else { return nil }
        return Table(template: best.template, rows: dataRows)
    }

    // MARK: - Kopregel

    /// De regel met de meeste herkende koppen van `template` (minstens
    /// `minimumHeaderColumns`, waarvan minstens twee echte velden).
    static func header(in rows: [[RecognizedTextBox]], template: ScreenshotTemplate) -> (index: Int, columns: [Column])? {
        guard let columnRules = template.columns, !columnRules.isEmpty else { return nil }

        // Langste koppen eerst, zodat "cum. net profit" niet als "profit" telt.
        let labels = columnRules
            .flatMap { key, rule in rule.labels.map { (key: key, words: words(of: $0)) } }
            .filter { !$0.words.isEmpty }
            .sorted {
                if $0.words.count != $1.words.count { return $0.words.count > $1.words.count }
                if $0.key != $1.key { return $0.key < $1.key }
                return $0.words.joined(separator: " ") < $1.words.joined(separator: " ")
            }

        var best: (index: Int, columns: [Column])?
        for (index, row) in rows.enumerated() {
            let rowTokens = row.flatMap { Self.tokens(of: $0) }
            let normalized = rowTokens.map { normalizeWord($0.text) }
            var used = Set<Int>()
            var matched: [Column] = []

            // Een veld komt één keer voor; kolommen die geen veld zijn
            // ("other") mogen vaker voorkomen.
            for label in labels where ScreenshotField(rawValue: label.key) == nil || !matched.contains(where: { $0.key == label.key }) {
                let length = label.words.count
                guard length <= rowTokens.count else { continue }
                for start in 0...(rowTokens.count - length) {
                    let range = start..<(start + length)
                    guard range.allSatisfy({ !used.contains($0) }),
                          Array(normalized[range]) == label.words else { continue }
                    used.formUnion(range)
                    matched.append(Column(key: label.key, minX: rowTokens[start].minX, maxX: rowTokens[start + length - 1].maxX))
                    break
                }
            }

            let fieldColumns = matched.filter { ScreenshotField(rawValue: $0.key) != nil }.count
            guard matched.count >= minimumHeaderColumns, fieldColumns >= 2 else { continue }
            if let current = best, current.columns.count >= matched.count { continue }
            best = (index, matched.sorted { $0.minX < $1.minX })
        }
        return best
    }

    // MARK: - Datarijen

    /// Ruwe tekst per kolomsleutel voor één regel. Een blok of cel die onder
    /// precies één kolomkop valt, gaat in zijn geheel naar die kolom (zo
    /// blijft "9/22/2025 9:31:22 AM" heel, ook als hij breder is dan de kop);
    /// anders gaat elk woord naar de kolom waar het het meest onder valt, of
    /// naar die van het woord ervoor in dezelfde cel, of de dichtstbijzijnde.
    static func values(in row: [RecognizedTextBox], columns: [Column]) -> [String: String] {
        var assigned: [String: [Token]] = [:]
        func assign(_ cellTokens: [Token], minX: CGFloat, maxX: CGFloat) {
            let overlapping = columns.filter { overlap(minX, maxX, $0) > 0 }
            if overlapping.count == 1 {
                assigned[overlapping[0].key, default: []].append(contentsOf: cellTokens)
                return
            }
            var previous: Column?
            for token in cellTokens {
                guard let column = overlapColumn(for: token, in: columns) ?? previous ?? nearestColumn(for: token, in: columns) else { continue }
                assigned[column.key, default: []].append(token)
                previous = column
            }
        }

        for box in row {
            let boxTokens = tokens(of: box)
            guard !boxTokens.isEmpty else { continue }
            if columns.filter({ overlap(box.boundingBox.minX, box.boundingBox.maxX, $0) > 0 }).count == 1 {
                assign(boxTokens, minX: box.boundingBox.minX, maxX: box.boundingBox.maxX)
                continue
            }
            var start = 0
            while start < boxTokens.count {
                var end = start
                while end + 1 < boxTokens.count, boxTokens[end + 1].cell == boxTokens[start].cell { end += 1 }
                let cell = Array(boxTokens[start...end])
                assign(cell, minX: cell[0].minX, maxX: cell[cell.count - 1].maxX)
                start = end + 1
            }
        }

        var result: [String: String] = [:]
        for (key, keyTokens) in assigned {
            let text = keyTokens.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ")
            if !text.isEmpty { result[key] = text }
        }
        return result
    }

    private static func overlapColumn(for token: Token, in columns: [Column]) -> Column? {
        columns
            .map { (column: $0, overlap: overlap(token.minX, token.maxX, $0)) }
            .filter { $0.overlap > 0 }
            .max { $0.overlap < $1.overlap }?
            .column
    }

    private static func nearestColumn(for token: Token, in columns: [Column]) -> Column? {
        columns.min { distance(token, $0) < distance(token, $1) }
    }

    private static func overlap(_ minX: CGFloat, _ maxX: CGFloat, _ column: Column) -> CGFloat {
        min(maxX, column.maxX) - max(minX, column.minX)
    }

    private static func distance(_ token: Token, _ column: Column) -> CGFloat {
        if token.maxX < column.minX { return column.minX - token.maxX }
        if token.minX > column.maxX { return token.minX - column.maxX }
        return 0
    }

    // MARK: - Woorden

    /// Woorden van een blok met hun x-bereik, evenredig met de plek van de
    /// tekens in de bloktekst.
    static func tokens(of box: RecognizedTextBox) -> [Token] {
        let text = box.text
        let count = CGFloat(max(text.count, 1))
        let rect = box.boundingBox
        var tokens: [Token] = []
        var offset = 0
        var start: Int?
        var current = ""
        var cell = 0
        var spaces = 0
        for character in text + " " {
            if character.isWhitespace {
                if let begin = start {
                    tokens.append(Token(
                        text: current,
                        minX: rect.minX + rect.width * CGFloat(begin) / count,
                        maxX: rect.minX + rect.width * CGFloat(offset) / count,
                        cell: cell
                    ))
                }
                start = nil
                current = ""
                spaces += 1
            } else {
                if start == nil {
                    if !tokens.isEmpty, spaces >= 2 { cell += 1 }
                    start = offset
                    spaces = 0
                }
                current.append(character)
            }
            offset += 1
        }
        return tokens
    }

    /// Kopwoord vergelijkbaar maken: kleine letters, zonder dubbele punt aan
    /// het eind ("Symbol:" = "symbol").
    static func normalizeWord(_ word: String) -> String {
        var text = word.lowercased()
        while text.hasSuffix(":") { text.removeLast() }
        return text
    }

    static func words(of label: String) -> [String] {
        label.split(whereSeparator: \.isWhitespace).map { normalizeWord(String($0)) }.filter { !$0.isEmpty }
    }
}
