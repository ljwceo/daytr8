import Foundation
import UserNotifications

/// Plant de lokale "vul je journal in"-herinnering via
/// `UNUserNotificationCenter` (geen push, geen entitlement nodig).
///
/// Bij elke wijziging van de instellingen worden alle eerder geplande
/// herinneringen van de app verwijderd en — als de herinnering aan staat —
/// opnieuw ingepland als herhalende kalender-trigger.
public final class ReminderService {

    public static let identifierPrefix = "journal-reminder"

    private let center: UNUserNotificationCenter
    private let settings: ReminderSettings

    public init(center: UNUserNotificationCenter = .current(), settings: ReminderSettings = ReminderSettings()) {
        self.center = center
        self.settings = settings
    }

    // MARK: - Pure planning

    /// Kalendercomponenten voor de herhalende triggers: één per werkdag
    /// (weekday 2 = maandag … 6 = vrijdag in de gregoriaanse kalender) of één
    /// dagelijkse trigger.
    public static func triggerComponents(hour: Int, minute: Int, weekdaysOnly: Bool) -> [DateComponents] {
        guard weekdaysOnly else {
            return [DateComponents(hour: hour, minute: minute)]
        }
        return (2...6).map { weekday in
            DateComponents(hour: hour, minute: minute, weekday: weekday)
        }
    }

    /// Alle identifiers die de app ooit gebruikt (dagelijks + per weekdag),
    /// zodat opnieuw inplannen nooit oude herinneringen laat staan.
    public static var allIdentifiers: [String] {
        ["\(identifierPrefix)-daily"] + (1...7).map { "\(identifierPrefix)-\($0)" }
    }

    static func identifier(for components: DateComponents) -> String {
        if let weekday = components.weekday { return "\(identifierPrefix)-\(weekday)" }
        return "\(identifierPrefix)-daily"
    }

    // MARK: - Toestemming

    /// Vraagt (indien nodig) toestemming voor meldingen. `true` als meldingen
    /// toegestaan zijn.
    public func requestAuthorization() async -> Bool {
        let current = await center.notificationSettings()
        switch current.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    public func isAuthorizationDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    // MARK: - Inplannen

    /// Verwijdert bestaande herinneringen en plant ze opnieuw volgens de
    /// instellingen. Geeft `false` als de herinnering aan staat maar er geen
    /// toestemming is.
    @discardableResult
    public func reschedule() async -> Bool {
        center.removePendingNotificationRequests(withIdentifiers: Self.allIdentifiers)
        guard settings.isEnabled else { return true }
        guard await requestAuthorization() else { return false }

        let content = UNMutableNotificationContent()
        content.title = "TradeJournal"
        content.body = settings.message
        content.sound = .default

        let components = Self.triggerComponents(hour: settings.hour, minute: settings.minute, weekdaysOnly: settings.weekdaysOnly)
        for item in components {
            let trigger = UNCalendarNotificationTrigger(dateMatching: item, repeats: true)
            let request = UNNotificationRequest(identifier: Self.identifier(for: item), content: content, trigger: trigger)
            try? await center.add(request)
        }
        return true
    }
}
