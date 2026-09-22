import Foundation
import LocalAuthentication

/// Optioneel app-slot met Face ID / Touch ID en terugval op de toegangscode
/// van het toestel (`LocalAuthentication`, `.deviceOwnerAuthentication`).
/// Vereist alleen `NSFaceIDUsageDescription` in de Info.plist — geen
/// entitlement.
///
/// Instellingen staan in `UserDefaults`; `defaults` is injecteerbaar voor tests.
public final class AppLockService {

    public enum Keys {
        public static let isEnabled = "appLock.isEnabled"
        public static let gracePeriod = "appLock.gracePeriod"
    }

    /// Keuzes voor hoe lang de app op de achtergrond mag staan zonder opnieuw
    /// te vergrendelen (seconden).
    public static let gracePeriodOptions: [TimeInterval] = [0, 60, 300, 900]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.isEnabled) }
        set { defaults.set(newValue, forKey: Keys.isEnabled) }
    }

    public var gracePeriod: TimeInterval {
        get { max(defaults.double(forKey: Keys.gracePeriod), 0) }
        set { defaults.set(max(newValue, 0), forKey: Keys.gracePeriod) }
    }

    // MARK: - Pure beslisregel

    /// Of de app bij (terugkeer naar) de voorgrond vergrendeld moet worden.
    ///
    /// - `backgroundedAt == nil` betekent een koude start: dan altijd
    ///   vergrendelen als het slot aan staat.
    public static func shouldLock(isEnabled: Bool, backgroundedAt: Date?, now: Date, gracePeriod: TimeInterval) -> Bool {
        guard isEnabled else { return false }
        guard let backgroundedAt else { return true }
        return now.timeIntervalSince(backgroundedAt) >= gracePeriod
    }

    // MARK: - Authenticatie

    /// Of het toestel biometrie of een toegangscode heeft ingesteld.
    public func canAuthenticate() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Naam van de beschikbare methode voor in de UI.
    public func methodName() -> String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "toegangscode"
        }
    }

    /// Toont de systeemprompt. `true` bij succes.
    public func authenticate(reason: String = "Ontgrendel je trading journal") async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Annuleren"
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
