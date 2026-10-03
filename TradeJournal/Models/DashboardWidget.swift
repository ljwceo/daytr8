import Foundation
import SwiftData

/// Eén widget op een dashboard. Type, grootte en instellingen staan als ruwe
/// tekst, zodat een backup van een nieuwere app-versie (met onbekende types)
/// zonder verlies terug te zetten is.
@Model
public final class DashboardWidget {

    public var id: UUID = UUID()
    /// Ruwe waarde van `DashboardWidgetType`.
    public var typeRaw: String = DashboardWidgetType.statistic.rawValue
    /// Ruwe waarde van `WidgetSize`.
    public var sizeRaw: String = WidgetSize.small.rawValue
    /// Volgorde binnen het dashboard (laag = boven).
    public var sortOrder: Int = 0
    /// `WidgetSettings` als JSON.
    public var settingsJSON: String = "{}"
    public var createdAt: Date = Date()

    public var dashboard: Dashboard?

    public init(
        id: UUID = UUID(),
        typeRaw: String,
        sizeRaw: String,
        sortOrder: Int = 0,
        settingsJSON: String = "{}",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.typeRaw = typeRaw
        self.sizeRaw = sizeRaw
        self.sortOrder = sortOrder
        self.settingsJSON = settingsJSON
        self.createdAt = createdAt
    }

    public init(type: DashboardWidgetType, size: WidgetSize, settings: WidgetSettings = WidgetSettings(), sortOrder: Int = 0, createdAt: Date = Date()) {
        self.id = UUID()
        self.typeRaw = type.rawValue
        self.sizeRaw = size.rawValue
        self.sortOrder = sortOrder
        self.settingsJSON = settings.jsonString
        self.createdAt = createdAt
    }

    /// `nil` voor een type dat deze app-versie niet kent.
    public var type: DashboardWidgetType? { DashboardWidgetType(rawValue: typeRaw) }

    public var size: WidgetSize {
        get { WidgetSize(rawValue: sizeRaw) ?? .large }
        set { sizeRaw = newValue.rawValue }
    }

    public var settings: WidgetSettings {
        get { WidgetSettings.from(json: settingsJSON) }
        set { settingsJSON = newValue.jsonString }
    }
}
