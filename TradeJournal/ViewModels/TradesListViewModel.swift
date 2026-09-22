import Foundation
import SwiftData

/// Filter-, zoek- en sorteerlogica voor het trade log (`TradesView`).
///
/// Houdt zelf geen `ModelContext` of `@Query` vast — de view geeft de al
/// opgehaalde trades door aan `filteredAndSorted`, zodat deze logica puur
/// en unit-testbaar blijft. Mutaties (dupliceren/verwijderen) lopen via
/// `TradeEditingService`.
@Observable
public final class TradesListViewModel {

    public enum SortOption: String, CaseIterable, Identifiable {
        case dateDescending
        case dateAscending
        case pnlDescending
        case pnlAscending

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .dateDescending: return "Nieuwste eerst"
            case .dateAscending: return "Oudste eerst"
            case .pnlDescending: return "Grootste winst eerst"
            case .pnlAscending: return "Grootste verlies eerst"
            }
        }
    }

    public enum QuickFilter: String, CaseIterable, Identifiable {
        case all
        case open
        case wins
        case losses
        case thisWeek
        case thisMonth

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .all: return "Alles"
            case .open: return "Open"
            case .wins: return "Winst"
            case .losses: return "Verlies"
            case .thisWeek: return "Deze week"
            case .thisMonth: return "Deze maand"
            }
        }
    }

    public var searchText: String = ""
    public var quickFilter: QuickFilter = .all
    public var sortOption: SortOption = .dateDescending
    public var directionFilter: TradeDirection?

    public let statsService: StatsService
    public let editingService: TradeEditingService

    public init(
        statsService: StatsService = StatsService(),
        editingService: TradeEditingService = TradeEditingService()
    ) {
        self.statsService = statsService
        self.editingService = editingService
    }

    public func metrics(for trade: Trade) -> TradeMetrics {
        statsService.metrics(for: trade)
    }

    /// Past zoekterm, snelfilter, richtingsfilter en sortering toe op
    /// `trades`. Puur, dus unit-testbaar zonder een levende `ModelContext`.
    public func filteredAndSorted(_ trades: [Trade], now: Date = Date(), calendar: Calendar = .current) -> [Trade] {
        var result = trades

        if let directionFilter {
            result = result.filter { $0.direction == directionFilter }
        }

        switch quickFilter {
        case .all:
            break
        case .open:
            result = result.filter { $0.isOpen }
        case .wins:
            result = result.filter { statsService.metrics(for: $0).outcome == .win }
        case .losses:
            result = result.filter { statsService.metrics(for: $0).outcome == .loss }
        case .thisWeek:
            if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) {
                result = result.filter { $0.entryDate >= weekAgo }
            }
        case .thisMonth:
            if let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) {
                result = result.filter { $0.entryDate >= monthAgo }
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { trade in
                trade.symbol.localizedCaseInsensitiveContains(query)
                    || trade.notes.localizedCaseInsensitiveContains(query)
                    || (trade.playbook?.name.localizedCaseInsensitiveContains(query) ?? false)
                    || (trade.account?.name.localizedCaseInsensitiveContains(query) ?? false)
                    || trade.tags.contains { $0.name.localizedCaseInsensitiveContains(query) }
                    || trade.confluences.contains { $0.name.localizedCaseInsensitiveContains(query) }
            }
        }

        switch sortOption {
        case .dateDescending:
            result.sort { ($0.exitDate ?? $0.entryDate) > ($1.exitDate ?? $1.entryDate) }
        case .dateAscending:
            result.sort { ($0.exitDate ?? $0.entryDate) < ($1.exitDate ?? $1.entryDate) }
        case .pnlDescending:
            result.sort { statsService.metrics(for: $0).netPnL > statsService.metrics(for: $1).netPnL }
        case .pnlAscending:
            result.sort { statsService.metrics(for: $0).netPnL < statsService.metrics(for: $1).netPnL }
        }

        return result
    }

    public func duplicate(_ trade: Trade, in context: ModelContext) {
        editingService.duplicate(trade, in: context)
    }

    public func delete(_ trade: Trade, from context: ModelContext) {
        editingService.delete(trade, from: context)
    }
}
