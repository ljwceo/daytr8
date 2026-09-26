import Foundation

/// Eén instellingswaarde uit `UserDefaults`, als Codable waarde zodat
/// instellingen in een backup mee kunnen (`BackupPayload.settings`).
public enum SettingValue: Codable, Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)

    /// Leest een waarde uit `UserDefaults`. `nil` voor ontbrekende of niet
    /// ondersteunde types (bijv. `Data`-bookmarks, die toestelgebonden zijn).
    public init?(defaultsObject object: Any?) {
        switch object {
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number as CFNumber) {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.intValue)
            }
        default:
            return nil
        }
    }

    /// De waarde zoals `UserDefaults.set(_:forKey:)` hem verwacht.
    public var defaultsObject: Any {
        switch self {
        case .string(let value): return value
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        }
    }
}
