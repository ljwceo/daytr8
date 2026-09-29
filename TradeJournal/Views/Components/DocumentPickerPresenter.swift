import UIKit
import UniformTypeIdentifiers

/// Toont de iOS-documentkiezer (`UIDocumentPickerViewController`) rechtstreeks
/// via UIKit, in plaats van SwiftUI's `.fileImporter`.
///
/// Waarom: één `.fileImporter` met wisselende `allowedContentTypes`, op een
/// view die ook een `.sheet` en `.confirmationDialog` heeft, riep op het
/// toestel niet betrouwbaar terug ("ik tik op het bestand en er gebeurt
/// niks"). Hier houden we de delegate zelf sterk vast en roepen we de
/// completion precies één keer aan, ook bij annuleren.
@MainActor
final class DocumentPickerPresenter {

    enum Mode: Equatable {
        /// Backupbestand: de .zip of een losse backup.json. Als kopie
        /// (`asCopy`): iOS downloadt het bestand (iCloud) en zet het in onze
        /// tijdelijke map vóórdat hij terugroept.
        case backupFile
        /// Een map (uitgepakte backup of map voor automatische backups).
        /// Géén kopie: voor de automatische backup is een bookmark naar de
        /// echte map nodig.
        case folder

        var contentTypes: [UTType] {
            switch self {
            // Géén `.folder` hier: dan zijn bestanden in de kiezer grijs.
            case .backupFile: return [.zip, .json, .data]
            case .folder: return [.folder]
            }
        }

        var asCopy: Bool { self == .backupFile }

        var logName: String {
            switch self {
            case .backupFile: return "backupbestand (zip/json, als kopie)"
            case .folder: return "map"
            }
        }
    }

    enum PresentError: LocalizedError, Equatable {
        case noWindow
        case alreadyPresenting
        case busy

        var errorDescription: String? {
            switch self {
            case .noWindow:
                return "De bestandskiezer kon niet geopend worden (geen venster gevonden)."
            case .alreadyPresenting:
                return "De bestandskiezer is al open."
            case .busy:
                return "Er wordt nog een ander scherm geopend of gesloten. Probeer het zo nog eens."
            }
        }
    }

    private let log: ImportDiagnosticsLog
    /// Sterk vastgehouden: `UIDocumentPickerViewController.delegate` is weak.
    private var activeCoordinator: DocumentPickerCoordinator?
    private weak var activePicker: UIDocumentPickerViewController?

    init(log: ImportDiagnosticsLog? = nil) {
        self.log = log ?? .shared
    }

    var isPresenting: Bool { activeCoordinator != nil }

    /// Toont de kiezer. `completion` krijgt de gekozen URL, of `nil` als de
    /// gebruiker annuleerde — altijd precies één keer.
    func present(_ mode: Mode, completion: @escaping (URL?) -> Void) throws {
        if let coordinator = activeCoordinator {
            // Kiezer verdwenen zonder terugmelding? Dan als geannuleerd
            // afsluiten, anders blijft elke volgende tik geblokkeerd.
            if activePicker?.presentingViewController == nil {
                log.record("Kiezer: vorige kiezer was al weg zonder terugmelding")
                coordinator.finish(with: nil)
            } else {
                log.record("Kiezer niet geopend", detail: "er staat al een kiezer open")
                throw PresentError.alreadyPresenting
            }
        }

        guard let top = Self.topViewController() else {
            log.record("Kiezer niet geopend", detail: "geen key window / root view controller")
            throw PresentError.noWindow
        }
        if top.isBeingPresented || top.isBeingDismissed {
            log.record("Kiezer niet geopend", detail: "\(type(of: top)) wordt nog getoond/gesloten")
            throw PresentError.busy
        }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: mode.contentTypes, asCopy: mode.asCopy)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true

        let log = self.log
        let coordinator = DocumentPickerCoordinator { [weak self] url in
            if let url {
                log.record("Kiezer: callback", detail: url.lastPathComponent)
            } else {
                log.record("Kiezer: geannuleerd")
            }
            self?.activeCoordinator = nil
            self?.activePicker = nil
            completion(url)
        }
        picker.delegate = coordinator
        activeCoordinator = coordinator
        activePicker = picker

        top.present(picker, animated: true)
        log.record(
            "Kiezer getoond",
            detail: "\(mode.logName); types: \(mode.contentTypes.map(\.identifier).joined(separator: ", ")); vanaf \(type(of: top))"
        )
    }

    /// De bovenste, niet-sluitende view controller van het actieve venster.
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScenes = scenes.filter { $0.activationState == .foregroundActive }
        let windows = (activeScenes.isEmpty ? scenes : activeScenes).flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first,
              var top = window.rootViewController else { return nil }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

/// Delegate van de documentkiezer. Los van de presenter, zodat de
/// afhandeling in unit tests direct aan te roepen is.
@MainActor
final class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {

    private var completion: ((URL?) -> Void)?

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
        super.init()
    }

    /// `true` zodra de completion is aangeroepen.
    var isFinished: Bool { completion == nil }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(with: urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(with: nil)
    }

    /// Roept de completion hooguit één keer aan.
    func finish(with url: URL?) {
        guard let completion else { return }
        self.completion = nil
        completion(url)
    }
}
