import Foundation
import Observation

/// Bewaart welke medailles behaald zijn en wanneer, in `UserDefaults`
/// (JSON), net als de andere instellingen. Gaat mee in de backup
/// (`SettingsMigrator.backedUpKeys`).
///
/// Eenmaal behaald blijft een medaille bewaard, ook als de trades die hem
/// opleverden later verwijderd worden.
@Observable
final class MedalStore {

    enum Keys {
        /// `String` (JSON): medaille-id → behaald op (seconden sinds 1970).
        static let unlocked = "medals.unlocked"
        /// `Bool`: de eerste (stille) berekening achteraf is gedaan.
        static let initialSyncDone = "medals.initialSyncDone"
    }

    /// De app-brede store (ook herladen na het terugzetten van een backup).
    static let shared = MedalStore()

    private(set) var unlocked: [String: Date]
    private(set) var hasCompletedInitialSync: Bool

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.unlocked = Self.load(from: defaults)
        self.hasCompletedInitialSync = defaults.bool(forKey: Keys.initialSyncDone)
    }

    func isUnlocked(_ id: String) -> Bool { unlocked[id] != nil }

    /// Leest opnieuw uit `UserDefaults` (na het terugzetten van een backup).
    func reload() {
        let stored = Self.load(from: defaults)
        if stored != unlocked { unlocked = stored }
        hasCompletedInitialSync = defaults.bool(forKey: Keys.initialSyncDone)
    }

    /// Voegt nieuw behaalde medailles toe; bestaande datums blijven staan.
    /// - Returns: de id's die echt nieuw waren.
    @discardableResult
    func record(_ achieved: [String: Date]) -> [String] {
        let new = achieved.filter { unlocked[$0.key] == nil }
        guard !new.isEmpty else { return [] }
        unlocked.merge(new) { existing, _ in existing }
        persist()
        return Array(new.keys)
    }

    func markInitialSyncDone() {
        hasCompletedInitialSync = true
        defaults.set(true, forKey: Keys.initialSyncDone)
    }

    private func persist() {
        let intervals = unlocked.mapValues(\.timeIntervalSince1970)
        guard let data = try? JSONEncoder().encode(intervals),
              let json = String(data: data, encoding: .utf8) else { return }
        defaults.set(json, forKey: Keys.unlocked)
    }

    private static func load(from defaults: UserDefaults) -> [String: Date] {
        guard let json = defaults.string(forKey: Keys.unlocked),
              let data = json.data(using: .utf8),
              let intervals = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        return intervals.mapValues { Date(timeIntervalSince1970: $0) }
    }
}
