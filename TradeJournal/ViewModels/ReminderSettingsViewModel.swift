import Foundation

/// Instellingen voor de lokale journal-herinnering. Wijzigingen worden
/// opgeslagen in `ReminderSettings` en direct opnieuw ingepland via
/// `ReminderService`.
@Observable
public final class ReminderSettingsViewModel {

    public var isEnabled: Bool
    public var time: Date
    public var weekdaysOnly: Bool
    public var message: String
    public private(set) var permissionDenied = false

    private let settings: ReminderSettings
    private let service: ReminderService
    private let calendar: Calendar

    public init(settings: ReminderSettings = ReminderSettings(), service: ReminderService? = nil, calendar: Calendar = .current) {
        self.settings = settings
        self.service = service ?? ReminderService(settings: settings)
        self.calendar = calendar
        self.isEnabled = settings.isEnabled
        self.weekdaysOnly = settings.weekdaysOnly
        self.message = settings.message
        self.time = calendar.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: Date()) ?? Date()
    }

    /// Slaat de huidige waarden op en plant de herinnering opnieuw in.
    @MainActor
    public func apply() async {
        let components = calendar.dateComponents([.hour, .minute], from: time)
        settings.isEnabled = isEnabled
        settings.hour = components.hour ?? ReminderSettings.defaultHour
        settings.minute = components.minute ?? ReminderSettings.defaultMinute
        settings.weekdaysOnly = weekdaysOnly
        settings.message = message

        let scheduled = await service.reschedule()
        permissionDenied = isEnabled && !scheduled
        if permissionDenied {
            // Zonder toestemming heeft "aan" geen effect; toon dat eerlijk.
            isEnabled = false
            settings.isEnabled = false
        }
    }
}
