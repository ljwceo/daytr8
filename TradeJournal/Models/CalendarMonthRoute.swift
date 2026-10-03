import Foundation

/// Verzoek om de Kalender-tab in de maandweergave van een bepaalde maand te
/// openen (bijv. na een tik op de jaar-heatmap op het dashboard).
///
/// Elk verzoek heeft een eigen `id`, zodat twee keer dezelfde maand openen
/// ook twee keer reageert.
struct CalendarMonthRoute: Equatable, Identifiable {
    let id: UUID
    let year: Int
    /// 1–12 (begrensd).
    let month: Int

    init(id: UUID = UUID(), year: Int, month: Int) {
        self.id = id
        self.year = year
        self.month = min(max(month, 1), 12)
    }
}
