import Foundation
import SwiftData

/// Bulk-import vanaf MT5-screenshots: OCR (Vision, op het toestel), het
/// controlescherm (bewerken, aan/uit, verwijderen, account/playbook/tag
/// voor alle geselecteerde) en opslaan met samenvatting.
@Observable
public final class MT5ImportViewModel {

    public enum Phase: Equatable {
        case picking
        case recognizing(current: Int, total: Int)
        case review
        case finished(MT5ImportSummary)
    }

    public private(set) var phase: Phase = .picking
    public private(set) var rows: [MT5ImportRow] = []
    public private(set) var screenshots: [Data] = []
    /// Dubbel op de screenshots en samengevoegd.
    public private(set) var mergedCount = 0
    /// Screenshots waarop geen enkele MT5-trade herkend is.
    public private(set) var unrecognizedScreenshots: [Int] = []
    public var message: String?

    /// Keuzes voor "alle geselecteerde" (account verplicht te kiezen, de rest optioneel).
    public var bulkAccountID: UUID?
    public var bulkPlaybookID: UUID?
    public var bulkTagID: UUID?

    /// Maximaal aantal screenshots per keer.
    public static let maxScreenshots = 10

    @ObservationIgnored private let recognizer: any ScreenshotTextRecognizing
    @ObservationIgnored private let parser: MT5HistoryParser
    @ObservationIgnored private let service: MT5ScreenshotImportService
    @ObservationIgnored private var validationContext = MT5ScreenshotImportService.ValidationContext()

    public init(
        recognizer: any ScreenshotTextRecognizing = VisionTextRecognizer(),
        parser: MT5HistoryParser = MT5HistoryParser(),
        service: MT5ScreenshotImportService = MT5ScreenshotImportService()
    ) {
        self.recognizer = recognizer
        self.parser = parser
        self.service = service
    }

    // MARK: - Afgeleid

    public var selectedCount: Int { rows.filter(\.isSelected).count }
    public var duplicateCount: Int { rows.filter(\.isDuplicateOfExisting).count }
    public var rowsWithIssues: Int { rows.filter { !$0.issues.isEmpty && !$0.isDuplicateOfExisting }.count }
    public var canImport: Bool { rows.contains { $0.isSelected && !$0.hasErrors } }

    // MARK: - OCR

    /// Leest alle screenshots (één voor één, op de achtergrond) en bouwt het
    /// controlescherm op.
    @MainActor
    public func recognize(_ images: [Data], existingTrades: [Trade], instruments: [Instrument], defaultAccountID: UUID?, now: Date = Date()) async {
        let images = Array(images.prefix(Self.maxScreenshots))
        guard !images.isEmpty else { return }
        screenshots = images
        message = nil
        unrecognizedScreenshots = []

        var parsedPerScreenshot: [[MT5ParsedTrade]] = []
        for (index, data) in images.enumerated() {
            phase = .recognizing(current: index + 1, total: images.count)
            do {
                let boxes = try await recognizer.recognizeBoxes(in: data)
                let trades = parser.parse(boxes)
                if trades.isEmpty { unrecognizedScreenshots.append(index) }
                parsedPerScreenshot.append(trades)
            } catch {
                unrecognizedScreenshots.append(index)
                parsedPerScreenshot.append([])
            }
        }

        validationContext = MT5ScreenshotImportService.makeContext(existingTrades: existingTrades, instruments: instruments, now: now)
        let prepared = service.prepare(parsedPerScreenshot, context: validationContext)
        rows = prepared.rows
        mergedCount = prepared.merged
        bulkAccountID = defaultAccountID

        if rows.isEmpty {
            message = "Geen MT5-trades herkend. Gebruik screenshots van de History-tab van de MetaTrader 5-app (iOS)."
            phase = .picking
        } else {
            if !unrecognizedScreenshots.isEmpty {
                message = "Op \(unrecognizedScreenshots.count == 1 ? "1 screenshot" : "\(unrecognizedScreenshots.count) screenshots") is niets herkend."
            }
            phase = .review
        }
    }

    // MARK: - Controlescherm

    public func toggle(_ id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }), !rows[index].hasErrors else { return }
        rows[index].isSelected.toggle()
    }

    public func setAllSelected(_ selected: Bool) {
        for index in rows.indices where !rows[index].hasErrors {
            rows[index].isSelected = selected && !rows[index].isDuplicateOfExisting
        }
    }

    public func delete(_ id: UUID) {
        rows.removeAll { $0.id == id }
        revalidate()
    }

    /// Past een regel aan. Elk gewijzigd veld telt als gecorrigeerd en is
    /// daarmee niet meer "onzeker gelezen". Daarna opnieuw gecontroleerd.
    public func update(_ id: UUID, _ change: (inout MT5ImportRow) -> Void) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let before = rows[index]
        var row = before
        change(&row)
        for field in MT5ParsedTrade.Field.allCases where Self.value(of: field, in: row) != Self.value(of: field, in: before) {
            row.editedFields.insert(field)
            row.isTruncated = row.isTruncated && !Self.isCompleteEnough(row)
        }
        rows[index] = row
        revalidate()
    }

    /// Bevestigt een onzeker gelezen veld zonder het te wijzigen.
    public func confirm(_ field: MT5ParsedTrade.Field, of id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].confirmedFields.insert(field)
        revalidate()
    }

    /// Account (en optioneel playbook/tag) voor alle geselecteerde regels.
    public func applyBulkToSelected() {
        for index in rows.indices where rows[index].isSelected {
            rows[index].accountID = bulkAccountID
            rows[index].playbookID = bulkPlaybookID
            rows[index].tagID = bulkTagID
        }
    }

    private func revalidate() {
        rows = service.validate(rows, context: validationContext)
    }

    private static func isCompleteEnough(_ row: MT5ImportRow) -> Bool {
        MT5ParsedTrade.Field.allCases.allSatisfy { row.hasValue($0) }
    }

    private static func value(of field: MT5ParsedTrade.Field, in row: MT5ImportRow) -> String {
        switch field {
        case .symbol: return row.symbol
        case .direction: return row.direction?.rawValue ?? ""
        case .volume: return row.volume.map { String($0) } ?? ""
        case .entryPrice: return row.entryPrice.map { String($0) } ?? ""
        case .exitPrice: return row.exitPrice.map { String($0) } ?? ""
        case .closeTime: return row.closeTime.map { String($0.timeIntervalSince1970) } ?? ""
        case .pnl: return row.pnl.map { String($0) } ?? ""
        }
    }

    // MARK: - Opslaan

    @MainActor
    @discardableResult
    public func importSelected(accounts: [Account], playbooks: [Playbook], tags: [Tag], instruments: [Instrument], in context: ModelContext, now: Date = Date()) -> MT5ImportSummary {
        // Account, playbook en tag gelden in één keer voor alle geselecteerde trades.
        applyBulkToSelected()
        let summary = service.commit(
            rows, merged: mergedCount, screenshots: screenshots,
            accounts: accounts, playbooks: playbooks, tags: tags, instruments: instruments,
            in: context, now: now
        )
        phase = .finished(summary)
        return summary
    }

    /// Opnieuw beginnen (andere screenshots kiezen).
    public func reset() {
        phase = .picking
        rows = []
        screenshots = []
        mergedCount = 0
        unrecognizedScreenshots = []
        message = nil
    }
}
