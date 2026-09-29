import Foundation
import os

private let incomingFileLogger = Logger(subsystem: "com.tradejournal.app", category: "IncomingFile")

/// Vangt bestanden op die via de Bestanden-app of het deelmenu ("Deel →
/// Daytr8") naar de app gestuurd worden (`.onOpenURL`) en houdt ze vast tot
/// de root view ze kan tonen — bijv. pas na het ontgrendelen van het app-slot.
///
/// Omdat `LSSupportsOpeningDocumentsInPlace` uit staat, levert iOS een kopie
/// in `Documents/Inbox` aan; daar is geen security scope voor nodig. Die kopie
/// ruimt `discard(_:)` weer op zodra de gebruiker klaar is.
@MainActor
@Observable
public final class IncomingFileRouter {

    /// Het binnengekomen bestand dat nog getoond moet worden.
    public private(set) var pendingURL: URL?

    /// Map waarin iOS binnenkomende kopieën zet (`Documents/Inbox`).
    private let inboxDirectory: URL

    public init(inboxDirectory: URL? = nil) {
        self.inboxDirectory = inboxDirectory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Inbox", isDirectory: true)
    }

    /// Neemt een binnenkomende URL aan als het een mogelijke backup is
    /// (`.zip`, `.json` of een map); andere bestanden worden genegeerd.
    public func receive(_ url: URL) {
        guard Self.isSupported(url) else {
            incomingFileLogger.notice("Genegeerd bestand: \(url.lastPathComponent, privacy: .public)")
            return
        }
        incomingFileLogger.info("Binnengekomen backup: \(url.lastPathComponent, privacy: .public)")
        pendingURL = url
    }

    /// Geeft het wachtende bestand terug en leegt `pendingURL`.
    @discardableResult
    public func consume() -> URL? {
        let url = pendingURL
        pendingURL = nil
        return url
    }

    /// Verwijdert een door iOS aangeleverde kopie uit `Documents/Inbox`.
    /// Bestanden buiten de Inbox blijven altijd staan.
    public func discard(_ url: URL) {
        guard isInInbox(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// `.zip`, `.json` (hoofdletterongevoelig) of een map; alleen file-URL's.
    public nonisolated static func isSupported(_ url: URL, fileManager: FileManager = .default) -> Bool {
        guard url.isFileURL else { return false }
        if ["zip", "json"].contains(url.pathExtension.lowercased()) { return true }
        if url.hasDirectoryPath { return true }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func isInInbox(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let inboxPath = inboxDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let filePath = url.resolvingSymlinksInPath().standardizedFileURL.path
        return filePath.hasPrefix(inboxPath.hasSuffix("/") ? inboxPath : inboxPath + "/")
    }
}
