import XCTest
import SwiftData
import UIKit
import UniformTypeIdentifiers
@testable import TradeJournal

/// Herstellen via de documentkiezer: het asynchrone inlezen in
/// `BackupViewModel.prepareRestore` en de delegate van de kiezer.
@MainActor
final class BackupRestoreAsyncTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var directory: URL!
    private var log: ImportDiagnosticsLog!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.models), configurations: [config])
        suiteName = "BackupRestoreAsyncTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("BackupRestoreAsyncTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        log = ImportDiagnosticsLog(fileURL: nil)
        context.insert(Trade(symbol: "NQ", direction: .long, entryDate: Date(), entryPrice: 100, quantity: 1))
        context.insert(Trade(symbol: "ES", direction: .short, entryDate: Date(), entryPrice: 5_000, quantity: 1))
        try context.save()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        container = nil
        try super.tearDownWithError()
    }

    private func makeViewModel() -> BackupViewModel {
        BackupViewModel(
            settings: BackupSettings(defaults: defaults),
            backupService: BackupService(settingsDefaults: nil),
            diagnostics: log
        )
    }

    private func makeZip() throws -> URL {
        try BackupService(settingsDefaults: nil).exportBackup(from: context, to: directory)
    }

    /// Zoals de Bestanden-app de zip uitpakt: een map met backup.json.
    private func makeExtractedFolder() throws -> URL {
        let reader = try ZipReader(url: try makeZip())
        let folder = directory.appendingPathComponent("TradeJournal-backup", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for path in reader.paths where !path.hasSuffix("/") {
            let target = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try reader.data(for: path).write(to: target)
        }
        return folder
    }

    // MARK: - prepareRestore

    func test_prepareRestore_zip_setsPendingRestore() async throws {
        let viewModel = makeViewModel()
        await viewModel.prepareRestore(from: try makeZip())

        XCTAssertEqual(viewModel.pendingRestore?.summary.tradeCount, 2)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isWorking)
        XCTAssertTrue(log.entries.contains { $0.step == "Archieftype" && $0.detail == "zip" })
        XCTAssertTrue(log.entries.contains { $0.step == "Samenvatting" })
    }

    func test_prepareRestore_extractedFolder_setsPendingRestore() async throws {
        let viewModel = makeViewModel()
        await viewModel.prepareRestore(from: try makeExtractedFolder())

        XCTAssertEqual(viewModel.pendingRestore?.summary.tradeCount, 2)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isWorking)
    }

    func test_prepareRestore_looseJSON_setsPendingRestore() async throws {
        let json = try makeExtractedFolder().appendingPathComponent(BackupService.payloadPath)
        let viewModel = makeViewModel()
        await viewModel.prepareRestore(from: json)

        XCTAssertEqual(viewModel.pendingRestore?.summary.tradeCount, 2)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isWorking)
    }

    /// Kopie van de kiezer (`asCopy`): wordt verplaatst, niet achtergelaten.
    func test_prepareRestore_temporaryCopy_isMovedAndRestorable() async throws {
        let zip = try makeZip()
        let viewModel = makeViewModel()
        await viewModel.prepareRestore(from: zip, isTemporaryCopy: true)

        XCTAssertEqual(viewModel.pendingRestore?.summary.tradeCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: zip.path))

        // Na bevestigen staat de backup in de database.
        viewModel.confirmRestore(into: context)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.pendingRestore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Trade>()), 2)
    }

    func test_prepareRestore_invalidFile_showsErrorWithFileName() async throws {
        let bogus = directory.appendingPathComponent("geen-backup.zip")
        try Data("dit is geen backup".utf8).write(to: bogus)
        let viewModel = makeViewModel()
        await viewModel.prepareRestore(from: bogus)

        XCTAssertNil(viewModel.pendingRestore)
        XCTAssertFalse(viewModel.isWorking)
        XCTAssertNil(viewModel.statusMessage)
        let message = try XCTUnwrap(viewModel.errorMessage)
        XCTAssertTrue(message.contains("geen-backup.zip"))
        XCTAssertTrue(log.entries.contains { $0.step == "Fout bij inlezen" })
    }

    func test_prepareRestore_missingFile_showsError() async {
        let viewModel = makeViewModel()
        await viewModel.prepareRestore(from: directory.appendingPathComponent("bestaat-niet.zip"))
        XCTAssertNil(viewModel.pendingRestore)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isWorking)
    }

    func test_cancelRestore_clearsPendingRestore() async throws {
        let viewModel = makeViewModel()
        await viewModel.prepareRestore(from: try makeZip())
        XCTAssertNotNil(viewModel.pendingRestore)
        viewModel.cancelRestore()
        XCTAssertNil(viewModel.pendingRestore)
        XCTAssertFalse(viewModel.isConfirmingRestore)
    }

    func test_pickerCancelled_showsStatus() {
        let viewModel = makeViewModel()
        viewModel.pickerCancelled()
        XCTAssertEqual(viewModel.statusMessage, "Geen bestand gekozen.")
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Documentkiezer

    func test_coordinator_pick_callsCompletionOnce() {
        var calls: [URL?] = []
        let coordinator = DocumentPickerCoordinator { calls.append($0) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip])
        let url = directory.appendingPathComponent("backup.zip")

        coordinator.documentPicker(picker, didPickDocumentsAt: [url])
        coordinator.documentPicker(picker, didPickDocumentsAt: [url])
        coordinator.documentPickerWasCancelled(picker)

        XCTAssertEqual(calls, [url])
        XCTAssertTrue(coordinator.isFinished)
    }

    func test_coordinator_cancel_callsCompletionOnceWithNil() {
        var calls: [URL?] = []
        let coordinator = DocumentPickerCoordinator { calls.append($0) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip])

        coordinator.documentPickerWasCancelled(picker)
        coordinator.documentPicker(picker, didPickDocumentsAt: [directory])

        XCTAssertEqual(calls.count, 1)
        XCTAssertNil(calls[0])
    }

    func test_coordinator_emptySelection_countsAsCancel() {
        var calls: [URL?] = []
        let coordinator = DocumentPickerCoordinator { calls.append($0) }
        coordinator.documentPicker(UIDocumentPickerViewController(forOpeningContentTypes: [.zip]), didPickDocumentsAt: [])
        XCTAssertEqual(calls.count, 1)
        XCTAssertNil(calls[0])
    }

    func test_pickerModes_fileAsCopyWithoutFolder_folderInPlace() {
        let file = DocumentPickerPresenter.Mode.backupFile
        XCTAssertTrue(file.asCopy)
        XCTAssertEqual(file.contentTypes, [.zip, .json, .data])
        XCTAssertFalse(file.contentTypes.contains(.folder))

        let folder = DocumentPickerPresenter.Mode.folder
        XCTAssertFalse(folder.asCopy)
        XCTAssertEqual(folder.contentTypes, [.folder])
    }
}
