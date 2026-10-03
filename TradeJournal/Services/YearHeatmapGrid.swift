import Foundation

/// Raster van de jaar-heatmap: kolommen = weken (maanden lopen horizontaal),
/// rijen = dagen van de week (beginnend op `calendar.firstWeekday`).
///
/// Puur rekenwerk, zodat de positie van elke dag en het omgekeerde (tik →
/// dag) testbaar zijn zonder UI.
public struct YearHeatmapGrid: Equatable, Sendable {

    /// Kolom waarin een maand begint (voor de maandlabels).
    public struct MonthMarker: Equatable, Sendable {
        public let month: Int
        public let column: Int
    }

    public let year: Int
    /// Alle dagen van het jaar (start van de dag), op volgorde.
    public let days: [Date]
    /// Aantal lege rijen vóór 1 januari in de eerste kolom.
    public let leadingEmptyRows: Int
    public let columnCount: Int
    public let monthMarkers: [MonthMarker]

    public static let rowCount = 7

    public init?(year: Int, calendar: Calendar = .current) {
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        guard let start = calendar.date(from: components),
              let interval = calendar.dateInterval(of: .year, for: start) else { return nil }

        var days: [Date] = []
        var cursor = calendar.startOfDay(for: interval.start)
        while cursor < interval.end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = calendar.startOfDay(for: next)
        }
        guard !days.isEmpty else { return nil }

        let leading = (calendar.component(.weekday, from: days[0]) - calendar.firstWeekday + 7) % 7
        self.year = year
        self.days = days
        self.leadingEmptyRows = leading
        self.columnCount = (days.count + leading + Self.rowCount - 1) / Self.rowCount

        var markers: [MonthMarker] = []
        for (index, day) in days.enumerated() where calendar.component(.day, from: day) == 1 {
            markers.append(MonthMarker(month: calendar.component(.month, from: day), column: (index + leading) / Self.rowCount))
        }
        self.monthMarkers = markers
    }

    /// Kolom en rij van de dag met index `dayIndex` (0 = 1 januari).
    public func position(ofDayAt dayIndex: Int) -> (column: Int, row: Int) {
        let slot = dayIndex + leadingEmptyRows
        return (slot / Self.rowCount, slot % Self.rowCount)
    }

    /// De maand (1–12) bij een horizontale positie in kolommen (`0` = linker-
    /// rand van de eerste kolom; fracties toegestaan).
    ///
    /// Een maand loopt van zijn begin-kolom (`monthMarkers`) tot de begin-
    /// kolom van de volgende maand; een kolom waarin een maand begint hoort
    /// dus bij die nieuwe maand. Links van januari geeft januari, rechts van
    /// december geeft december.
    public func month(atColumn column: Double) -> Int {
        guard let first = monthMarkers.first else { return 1 }
        guard column.isFinite else { return column > 0 ? (monthMarkers.last?.month ?? 12) : first.month }
        var month = first.month
        for marker in monthMarkers where Double(marker.column) <= column {
            month = marker.month
        }
        return month
    }

    /// De maand bij een tik op `x` punten vanaf de linkerrand van de heatmap,
    /// met `leadingInset` punten voor de weekdaglabels en `cellSize` punten
    /// per kolom. Een tik op de labels of naast het raster telt ook.
    public func month(atX x: Double, leadingInset: Double, cellSize: Double) -> Int {
        guard cellSize > 0 else { return monthMarkers.first?.month ?? 1 }
        return month(atColumn: (x - leadingInset) / cellSize)
    }

    /// De dag op `column`/`row`, of `nil` buiten het jaar.
    public func day(column: Int, row: Int) -> Date? {
        guard column >= 0, row >= 0, row < Self.rowCount else { return nil }
        let index = column * Self.rowCount + row - leadingEmptyRows
        guard index >= 0, index < days.count else { return nil }
        return days[index]
    }
}
