import Foundation
import Observation

/// Logboek van elke stap bij het kiezen en inlezen van een backup, zodat een
/// probleem op het toestel ("ik tik en er gebeurt niks") achteraf te volgen
/// is: de gebruiker kopieert of deelt het vanuit Meer → Backup & herstel →
/// Importlogboek.
///
/// - Ringbuffer van `capacity` regels (oudste valt eraf).
/// - Persistent als JSON in Application Support (niet in Documents, zodat het
///   niet in de Bestanden-app of in backups opduikt).
/// - Bevat alleen bestandsnamen, types en foutcodes — geen journal-inhoud.
@MainActor
@Observable
public final class ImportDiagnosticsLog {

    public struct Entry: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        public let date: Date
        public let step: String
        public let detail: String?

        public init(id: UUID = UUID(), date: Date, step: String, detail: String?) {
            self.id = id
            self.date = date
            self.step = step
            self.detail = detail
        }
    }

    public static let defaultCapacity = 300
    /// Langere details worden afgekapt, zodat één regel het logboek niet vult.
    public static let maxDetailLength = 600

    /// Het logboek van de app.
    public static let shared = ImportDiagnosticsLog(fileURL: ImportDiagnosticsLog.defaultFileURL)

    public private(set) var entries: [Entry] = []
    public let capacity: Int

    private let fileURL: URL?
    private let now: () -> Date

    /// - Parameters:
    ///   - fileURL: waar het logboek bewaard wordt; `nil` = alleen in het geheugen.
    ///   - capacity: maximaal aantal regels.
    ///   - now: klok (injecteerbaar voor tests).
    public init(fileURL: URL?, capacity: Int = 300, now: @escaping () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.capacity = max(1, capacity)
        self.now = now
        self.entries = Self.load(from: fileURL, capacity: self.capacity)
    }

    /// `Application Support/Diagnostics/import-log.json`.
    public nonisolated static var defaultFileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return support
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("import-log.json")
    }

    // MARK: - Schrijven

    public func record(_ step: String, detail: String? = nil) {
        var trimmed = detail
        if let text = detail, text.count > Self.maxDetailLength {
            trimmed = String(text.prefix(Self.maxDetailLength)) + "…"
        }
        entries.append(Entry(date: now(), step: step, detail: trimmed))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        save()
    }

    /// Logt een fout met domein en code (bijv. `NSCocoaErrorDomain 260`).
    public func record(error: Error, step: String) {
        record(step, detail: Self.describe(error))
    }

    public func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - Export

    /// Het hele logboek als tekst, met een kop (appversie, build, iOS-versie)
    /// zodat een gedeeld logboek bij de juiste build te plaatsen is.
    public func exportText() -> String {
        var lines = [
            "Daytr8 – importlogboek",
            "App: \(Self.appVersionDescription)",
            "iOS: \(Self.systemVersion)",
            "Geëxporteerd: \(Self.timestampFormatter.string(from: now()))",
            "Regels: \(entries.count)",
            ""
        ]
        for entry in entries {
            lines.append(Self.line(for: entry))
        }
        return lines.joined(separator: "\n")
    }

    public static func line(for entry: Entry) -> String {
        let stamp = timestampFormatter.string(from: entry.date)
        if let detail = entry.detail, !detail.isEmpty {
            return "\(stamp)  \(entry.step) — \(detail)"
        }
        return "\(stamp)  \(entry.step)"
    }

    // MARK: - Versie-informatie

    /// "Versie 0.1.0 (build 1)" uit `Bundle.main`.
    public nonisolated static var appVersionDescription: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Versie \(version) (build \(build))"
    }

    /// Bijv. "18.1.0".
    public nonisolated static var systemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// Fout als "omschrijving [domein code]", ook voor onderliggende fouten.
    public nonisolated static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var text = "\(error.localizedDescription) [\(nsError.domain) \(nsError.code)]"
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " ← [\(underlying.domain) \(underlying.code)] \(underlying.localizedDescription)"
        }
        return text
    }

    // MARK: - Opslag

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static func load(from url: URL?, capacity: Int) -> [Entry] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let stored = try? decoder.decode([Entry].self, from: data) else { return [] }
        return Array(stored.suffix(capacity))
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            // Logboek is best effort; een schrijffout mag de import niet raken.
        }
    }
}
