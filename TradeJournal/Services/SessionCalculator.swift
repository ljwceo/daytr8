import Foundation

/// Bepaalt de handelssessie (Asia / London / NY AM / NY PM) op basis van de
/// entry-tijd van een trade.
///
/// De sessies zijn gedefinieerd in "lokale tijd" van de geconfigureerde
/// tijdzone. Standaard gebruiken we `America/New_York` en de klassieke ICT-tijden.
/// Alles is aanpasbaar in de instellingen zonder de code te wijzigen.
public struct SessionCalculator: Sendable {

    /// Windowdefinitie in minuten sinds middernacht (inclusief start, exclusief eind).
    /// Als `startMinutes > endMinutes` wraps het venster rond middernacht.
    public struct Window: Sendable, Equatable {
        public let session: Session
        public let startMinutes: Int
        public let endMinutes: Int

        public init(session: Session, startHour: Int, startMinute: Int = 0, endHour: Int, endMinute: Int = 0) {
            self.session = session
            self.startMinutes = startHour * 60 + startMinute
            self.endMinutes = endHour * 60 + endMinute
        }

        public init(session: Session, startMinutes: Int, endMinutes: Int) {
            self.session = session
            self.startMinutes = startMinutes
            self.endMinutes = endMinutes
        }

        public func contains(minutesOfDay minute: Int) -> Bool {
            if startMinutes == endMinutes { return false }
            if startMinutes < endMinutes {
                return minute >= startMinutes && minute < endMinutes
            } else {
                // Wraps rond middernacht (bijv. 20:00 - 05:00).
                return minute >= startMinutes || minute < endMinutes
            }
        }
    }

    // MARK: - Configuratie

    public var timeZone: TimeZone
    public var windows: [Window]

    public init(timeZone: TimeZone, windows: [Window]) {
        self.timeZone = timeZone
        self.windows = windows
    }

    // MARK: - Standaardconfiguratie

    /// Standaardsessies zoals ICT-traders ze gebruiken (New Yorkse tijd):
    /// - Asia:   20:00 – 02:00 (previous day evening → early morning NY)
    /// - London: 02:00 – 08:00
    /// - NY AM:  08:00 – 12:00
    /// - NY PM:  12:00 – 17:00
    public static let defaultWindows: [Window] = [
        Window(session: .asia,   startHour: 20, endHour: 2),
        Window(session: .london, startHour: 2,  endHour: 8),
        Window(session: .nyAM,   startHour: 8,  endHour: 12),
        Window(session: .nyPM,   startHour: 12, endHour: 17)
    ]

    /// Default calculator: America/New_York + standaardvensters.
    public static let `default`: SessionCalculator = SessionCalculator(
        timeZone: TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: -5 * 3600)!,
        windows: defaultWindows
    )

    // MARK: - API

    /// Bepaalt de sessie waar `date` in valt. Valt `date` in geen enkel venster,
    /// wordt `.other` teruggegeven.
    public func session(for date: Date) -> Session {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        for w in windows where w.contains(minutesOfDay: minute) {
            return w.session
        }
        return .other
    }
}
