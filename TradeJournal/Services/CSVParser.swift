import Foundation

/// Een geparste CSV-tabel: één kopregel plus de datarijen.
///
/// Rijen zijn altijd precies `headers.count` breed: te korte rijen worden
/// aangevuld met lege strings, te lange rijen worden afgekapt. Zo kan de rest
/// van de import-pipeline veilig op kolomindex werken.
public struct CSVTable: Equatable, Sendable {
    public let headers: [String]
    public let rows: [[String]]
    /// Het gedetecteerde (of opgegeven) scheidingsteken.
    public let delimiter: Character

    public init(headers: [String], rows: [[String]], delimiter: Character = ",") {
        self.headers = headers
        self.rows = rows
        self.delimiter = delimiter
    }

    /// Waarde op `row`/`column`, of `nil` als de index buiten de tabel valt.
    public func value(row: Int, column: Int) -> String? {
        guard rows.indices.contains(row), headers.indices.contains(column) else { return nil }
        return rows[row][column]
    }
}

/// RFC 4180-achtige CSV-parser zonder externe dependencies.
///
/// Ondersteunt:
/// - komma, puntkomma en tab als scheidingsteken (automatisch gedetecteerd);
/// - velden tussen dubbele quotes, inclusief `""` als escape en regeleinden
///   binnen een veld;
/// - `\n`, `\r\n` en losse `\r` als regeleinde;
/// - een UTF-8 byte order mark aan het begin;
/// - lege regels (worden overgeslagen).
///
/// Puur en synchroon, zodat hij direct unit-testbaar is.
public enum CSVParser {

    public enum ParseError: Error, Equatable, LocalizedError {
        case empty
        case unreadableEncoding

        public var errorDescription: String? {
            switch self {
            case .empty: return "Het CSV-bestand is leeg of bevat geen kopregel."
            case .unreadableEncoding: return "Het CSV-bestand kon niet als tekst gelezen worden (onbekende codering)."
            }
        }
    }

    /// Parseert ruwe bytes. Probeert UTF-8, dan UTF-16 en Windows-1252 (Excel-exports).
    public static func parse(data: Data, delimiter: Character? = nil) throws -> CSVTable {
        guard let text = decode(data) else { throw ParseError.unreadableEncoding }
        return try parse(text, delimiter: delimiter)
    }

    /// Parseert een CSV-string. Het eerste niet-lege record is de kopregel.
    public static func parse(_ text: String, delimiter: Character? = nil) throws -> CSVTable {
        var body = text
        if body.hasPrefix("\u{FEFF}") { body.removeFirst() }

        let separator = delimiter ?? detectDelimiter(in: body)
        let records = parseRecords(body, delimiter: separator)
            .filter { record in !record.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }

        guard let headerRecord = records.first else { throw ParseError.empty }
        let headers = headerRecord.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let width = headers.count

        let rows: [[String]] = records.dropFirst().map { record in
            var row = Array(record.prefix(width))
            if row.count < width {
                row.append(contentsOf: Array(repeating: "", count: width - row.count))
            }
            return row
        }
        return CSVTable(headers: headers, rows: rows, delimiter: separator)
    }

    /// Kiest het scheidingsteken dat in de eerste regel (buiten quotes) het
    /// vaakst voorkomt. Valt terug op een komma.
    public static func detectDelimiter(in text: String) -> Character {
        let candidates: [Character] = [",", ";", "\t"]
        var counts: [Character: Int] = [:]
        var inQuotes = false
        for char in text {
            if char == "\"" { inQuotes.toggle(); continue }
            // `isNewline` vangt ook "\r\n", dat in Swift één Character is.
            if !inQuotes && char.isNewline { break }
            if !inQuotes && candidates.contains(char) {
                counts[char, default: 0] += 1
            }
        }
        var best: Character = ","
        var bestCount = 0
        for candidate in candidates where (counts[candidate] ?? 0) > bestCount {
            best = candidate
            bestCount = counts[candidate] ?? 0
        }
        return best
    }

    // MARK: - Intern

    private static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let utf16 = String(data: data, encoding: .utf16) {
            return utf16
        }
        return String(data: data, encoding: .windowsCP1252)
    }

    /// State machine over de unicode scalars. Werkt op scalars i.p.v.
    /// `Character`s zodat `\r\n` (één grapheme cluster) correct herkend wordt.
    private static func parseRecords(_ text: String, delimiter: Character) -> [[String]] {
        let delimiterScalar = delimiter.unicodeScalars.first!
        let quote: Unicode.Scalar = "\""
        let cr: Unicode.Scalar = "\r"
        let lf: Unicode.Scalar = "\n"

        var records: [[String]] = []
        var record: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false

        let scalars = Array(text.unicodeScalars)
        var index = 0

        func endField() {
            record.append(String(field))
            field = String.UnicodeScalarView()
        }

        func endRecord() {
            endField()
            records.append(record)
            record = []
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if inQuotes {
                if scalar == quote {
                    if index + 1 < scalars.count && scalars[index + 1] == quote {
                        field.append(quote)
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(scalar)
                }
            } else {
                switch scalar {
                case quote where field.isEmpty:
                    inQuotes = true
                case delimiterScalar:
                    endField()
                case cr:
                    endRecord()
                    if index + 1 < scalars.count && scalars[index + 1] == lf {
                        index += 1
                    }
                case lf:
                    endRecord()
                default:
                    field.append(scalar)
                }
            }
            index += 1
        }

        if !field.isEmpty || !record.isEmpty {
            endRecord()
        }
        return records
    }
}

/// Bouwt CSV-tekst op volgens RFC 4180 (komma-gescheiden, `\r\n`-regeleinden).
public enum CSVWriter {

    /// Zet een kopregel en rijen om naar CSV-tekst.
    public static func write(headers: [String], rows: [[String]]) -> String {
        var lines: [String] = [line(headers)]
        lines.reserveCapacity(rows.count + 1)
        for row in rows {
            lines.append(line(row))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Eén regel, met correct gequote velden.
    public static func line(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }

    /// Quote een veld als het een komma, quote of regeleinde bevat, of met
    /// spaties begint/eindigt.
    public static func escape(_ field: String) -> String {
        let needsQuotes = field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r")
            || field.hasPrefix(" ") || field.hasSuffix(" ")
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
