import Foundation
import SwiftData

/// Viewmodel achter `CSVImportView`: bestand inlezen → preset/kolommapping
/// kiezen → voorbeeld met duplicaten → importeren.
///
/// Alle echte logica zit in `CSVParser`, `CSVImportPresets` en
/// `CSVImportService`; dit viewmodel houdt alleen de stap-state vast.
@Observable
public final class CSVImportViewModel {

    // MARK: - Bestand

    public private(set) var table: CSVTable?
    public private(set) var fileName: String = ""
    public var errorMessage: String?

    // MARK: - Mapping

    /// `nil` = eigen mapping (geen preset).
    public private(set) var selectedPresetID: String?
    public var mapping = CSVColumnMapping(mode: .fills)
    public var account: Account?

    // MARK: - Voorbeeld & resultaat

    public private(set) var extraction: CSVImportService.ExtractionResult?
    public private(set) var previewItems: [CSVImportService.PreviewItem] = []
    public var includeDuplicates = false
    public private(set) var importedCount: Int?

    private let service: CSVImportService

    public init(service: CSVImportService = CSVImportService()) {
        self.service = service
    }

    // MARK: - Stap 1: bestand

    /// Leest een bestand uit de document picker (security-scoped URL).
    public func loadFile(at url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            load(data: data, fileName: url.lastPathComponent)
        } catch {
            errorMessage = "Het bestand kon niet geopend worden: \(error.localizedDescription)"
        }
    }

    /// Parseert CSV-bytes en kiest automatisch de best passende preset.
    public func load(data: Data, fileName: String) {
        resetResults()
        do {
            let parsed = try CSVParser.parse(data: data)
            table = parsed
            self.fileName = fileName
            errorMessage = nil
            if let detected = CSVImportPresets.detectOrGeneric(headers: parsed.headers) {
                applyPreset(id: detected.id)
            } else {
                selectedPresetID = nil
                mapping = CSVColumnMapping(mode: .fills, dateOrder: mapping.dateOrder, timeZoneIdentifier: mapping.timeZoneIdentifier)
            }
        } catch {
            table = nil
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Stap 2: mapping

    public var headers: [String] { table?.headers ?? [] }

    public var selectedPreset: CSVImportPreset? {
        selectedPresetID.flatMap(CSVImportPresets.preset(id:))
    }

    /// Past een preset toe op de huidige kopregel; `nil` start een lege mapping
    /// in de huidige modus.
    public func applyPreset(id: String?) {
        resetResults()
        selectedPresetID = id
        if let id, let preset = CSVImportPresets.preset(id: id) {
            mapping = preset.mapping(for: headers, timeZoneIdentifier: mapping.timeZoneIdentifier)
        } else {
            mapping = CSVColumnMapping(mode: mapping.mode, dateOrder: mapping.dateOrder, timeZoneIdentifier: mapping.timeZoneIdentifier)
        }
    }

    public func setMode(_ mode: CSVImportMode) {
        guard mode != mapping.mode else { return }
        resetResults()
        selectedPresetID = nil
        mapping = CSVColumnMapping(mode: mode, dateOrder: mapping.dateOrder, timeZoneIdentifier: mapping.timeZoneIdentifier)
    }

    /// Koppelt `field` aan kolom `column` (of ontkoppelt bij `nil`).
    public func setColumn(_ column: Int?, for field: CSVImportField) {
        resetResults()
        selectedPresetID = nil
        mapping.columns[field] = column
    }

    public func column(for field: CSVImportField) -> Int? {
        mapping.columns[field]
    }

    /// Eerste niet-lege waarde in de gekoppelde kolom, als hulp in de UI.
    public func sampleValue(for field: CSVImportField) -> String? {
        guard let table, let column = mapping.columns[field] else { return nil }
        for row in table.rows.prefix(20) where row.indices.contains(column) {
            let value = row[column].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    public var validationErrors: [String] {
        table == nil ? ["Kies eerst een CSV-bestand."] : mapping.validationErrors
    }

    public var canBuildPreview: Bool { validationErrors.isEmpty }

    // MARK: - Stap 3: voorbeeld

    public func buildPreview(existingTrades: [Trade], instruments: [Instrument]) {
        guard let table, canBuildPreview else { return }
        let known = CSVImportService.knownSymbols(instruments: instruments)
        let result = service.extract(from: table, mapping: mapping, knownSymbols: known)
        extraction = result
        previewItems = service.preview(result.trades, existingTrades: existingTrades, knownSymbols: known)
        importedCount = nil
    }

    public var duplicateCount: Int { previewItems.filter(\.isDuplicate).count }
    public var newCount: Int { previewItems.count - duplicateCount }
    public var tradesToImportCount: Int { includeDuplicates ? previewItems.count : newCount }
    public var unknownInstrumentSymbols: [String] {
        Array(Set(previewItems.filter { !$0.hasKnownInstrument }.map(\.trade.symbol))).sorted()
    }

    // MARK: - Stap 4: importeren

    @discardableResult
    public func importTrades(instruments: [Instrument], accounts: [Account] = [], in context: ModelContext) -> Int {
        let created = service.commit(
            previewItems,
            includeDuplicates: includeDuplicates,
            account: account,
            accounts: accounts,
            instruments: instruments,
            in: context
        )
        importedCount = created.count
        return created.count
    }

    // MARK: - Intern

    private func resetResults() {
        extraction = nil
        previewItems = []
        importedCount = nil
    }
}
