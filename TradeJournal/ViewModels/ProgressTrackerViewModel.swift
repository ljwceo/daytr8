import Foundation
import SwiftData

/// Progress tracker (SPEC §10): checklist van vandaag (of een gekozen dag),
/// streak, consistentie en de consistentie-kalender, plus beheer van de
/// dagelijkse regels.
@Observable
public final class ProgressTrackerViewModel {

    /// Bewerkbare velden van een regel.
    public struct RuleDraft: Equatable {
        public var name: String = ""
        public var kind: DailyRuleKind = .manual
        public var threshold: Double = 0
        public var isActive: Bool = true

        public init() {}

        public init(from rule: DailyRule) {
            name = rule.name
            kind = rule.kind
            threshold = rule.threshold
            isActive = rule.isActive
        }

        public var isValid: Bool {
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (!kind.usesThreshold || threshold > 0)
        }
    }

    /// Aantal weken in de consistentie-kalender.
    public static let heatmapWeeks = 16

    public let service: ProgressTrackerService
    public let calendar: Calendar
    public var selectedDate: Date

    public init(service: ProgressTrackerService = ProgressTrackerService(), calendar: Calendar = .current, today: Date = Date()) {
        self.service = service
        self.calendar = calendar
        self.selectedDate = calendar.startOfDay(for: today)
    }

    // MARK: - Berekeningen

    public func dayProgress(
        for date: Date,
        rules: [DailyRule],
        trades: [Trade],
        journals: [DailyJournal],
        checks: [DailyRuleCheck]
    ) -> DayProgress {
        let dayTrades = trades.filter { calendar.isDate($0.exitDate ?? $0.entryDate, inSameDayAs: date) }
        let journal = journals.first { calendar.isDate($0.date, inSameDayAs: date) }
        return service.evaluate(rules: rules, on: date, dayTrades: dayTrades, journal: journal, checks: checks, calendar: calendar)
    }

    public func allProgress(rules: [DailyRule], trades: [Trade], journals: [DailyJournal], checks: [DailyRuleCheck]) -> [Date: DayProgress] {
        service.progress(rules: rules, trades: trades, journals: journals, checks: checks, calendar: calendar)
    }

    public func summary(for progress: [Date: DayProgress], today: Date = Date()) -> ProgressSummary {
        service.summary(for: progress, today: today, calendar: calendar)
    }

    /// Raster voor de consistentie-kalender: `weeks` kolommen (oud → nieuw)
    /// van 7 dagen, beginnend op `calendar.firstWeekday`; de laatste kolom
    /// bevat `today`. Dagen na vandaag zijn `nil`.
    public func heatmapWeeks(endingOn today: Date = Date(), weeks: Int = ProgressTrackerViewModel.heatmapWeeks) -> [[Date?]] {
        let todayStart = calendar.startOfDay(for: today)
        guard weeks > 0, let currentWeek = calendar.dateInterval(of: .weekOfYear, for: todayStart) else { return [] }
        let currentWeekStart = calendar.startOfDay(for: currentWeek.start)

        return (0..<weeks).reversed().map { offset in
            let weekStart = calendar.date(byAdding: .day, value: -7 * offset, to: currentWeekStart) ?? currentWeekStart
            return (0..<7).map { dayOffset -> Date? in
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { return nil }
                return day <= todayStart ? day : nil
            }
        }
    }

    // MARK: - Afvinken

    /// Vinkt een handmatige regel af voor `date`, of zet hem terug.
    public func toggleCheck(for rule: DailyRule, on date: Date, in context: ModelContext) {
        let day = calendar.startOfDay(for: date)
        if let existing = rule.checks.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
            existing.isFollowed.toggle()
        } else {
            let check = DailyRuleCheck(date: day, isFollowed: true)
            context.insert(check)
            check.rule = rule
        }
    }

    // MARK: - Regelbeheer

    @discardableResult
    public func saveRule(_ draft: RuleDraft, existing: DailyRule?, allRules: [DailyRule], in context: ModelContext, now: Date = Date()) -> DailyRule? {
        guard draft.isValid else { return nil }
        let rule: DailyRule
        if let existing {
            rule = existing
        } else {
            rule = DailyRule(name: "", kind: draft.kind, sortOrder: (allRules.map(\.sortOrder).max() ?? -1) + 1, createdAt: now)
            context.insert(rule)
        }
        rule.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.kind = draft.kind
        rule.threshold = draft.kind.usesThreshold ? draft.threshold : 0
        rule.isActive = draft.isActive
        return rule
    }

    public func deleteRule(_ rule: DailyRule, in context: ModelContext) {
        context.delete(rule)
    }

    /// Nieuwe volgorde na slepen in de lijst.
    public func moveRules(_ rules: [DailyRule], from source: IndexSet, to destination: Int) {
        // Zelfde semantiek als SwiftUI's `move(fromOffsets:toOffset:)`,
        // zonder SwiftUI in de viewmodel te importeren.
        let moving = source.sorted().map { rules[$0] }
        var ordered = rules.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertionIndex = min(max(destination - source.filter { $0 < destination }.count, 0), ordered.count)
        ordered.insert(contentsOf: moving, at: insertionIndex)
        for (index, rule) in ordered.enumerated() {
            rule.sortOrder = index
        }
    }
}
