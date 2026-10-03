import Foundation
import Observation
import SwiftData

/// App-brede staat voor rewards: de animatie na het opslaan van een trade
/// (incl. hot streak), medaillemeldingen (toasts, één voor één) en het
/// medaille-overzicht. Gedeeld via de environment (net als `OnboardingViewModel`);
/// `RootTabView` toont de overlays.
@Observable
final class RewardsViewModel {

    /// De animatie na het opslaan van een nieuwe trade.
    struct Celebration: Identifiable, Equatable {
        let id = UUID()
        let outcome: TradeOutcome
        let netPnL: Double
        let currency: String
        /// Winnende trades op rij (inclusief deze); 0 als de trade geen winst was.
        let winStreak: Int

        /// Vanaf 3 winsten op rij: hot streak.
        var isHotStreak: Bool { winStreak >= RewardsViewModel.hotStreakMinimum }

        /// 0 (3 op rij) … 1 (15 of meer op rij): kleur, grootte en aantal deeltjes.
        var intensity: Double {
            guard isHotStreak else { return 0 }
            return min(Double(winStreak - RewardsViewModel.hotStreakMinimum) / 12, 1)
        }
    }

    /// Eén melding in de wachtrij.
    enum Toast: Identifiable, Equatable {
        case medal(MedalDefinition, Date)
        /// Samenvatting als er in één keer veel medailles bijkomen (bijv. de
        /// eerste berekening achteraf of na een import).
        case summary(count: Int, isInitial: Bool)

        var id: String {
            switch self {
            case .medal(let definition, _): return definition.id
            case .summary(let count, let isInitial): return "summary-\(count)-\(isInitial)"
            }
        }
    }

    static let hotStreakMinimum = 3
    /// Meer nieuwe medailles tegelijk dan dit → één samenvatting i.p.v. losse meldingen.
    static let maximumIndividualToasts = 4
    /// Hoe lang een melding blijft staan.
    static let toastDuration: Duration = .seconds(3.5)

    private(set) var celebration: Celebration?
    private(set) var currentToast: Toast?
    private(set) var evaluation: MedalEvaluation = .empty

    /// Tab waar `RootTabView` naartoe moet (na de animatie: Rapporten).
    var requestedTab: AppTab?

    var isOverviewPresented = false
    /// Medaille die het overzicht bij openen uitlicht.
    var highlightedMedalID: String?

    @ObservationIgnored private var queue: [Toast] = []
    @ObservationIgnored let store: MedalStore
    @ObservationIgnored private let service: MedalService
    /// Vingerafdruk van de trades bij de laatste sync (zie `sync(in:)`).
    @ObservationIgnored private var lastSyncFingerprint: String?
    @ObservationIgnored private let settings: RewardSettings
    @ObservationIgnored private let statsService = StatsService()

    init(store: MedalStore = .shared, service: MedalService = MedalService(), settings: RewardSettings = RewardSettings()) {
        self.store = store
        self.service = service
        self.settings = settings
    }

    // MARK: - Medailles

    var unlockedCount: Int { store.unlocked.count }
    var totalCount: Int { MedalCatalog.all.count }

    /// Berekent de medailles opnieuw (app-start, terugkeer naar de app).
    ///
    /// De eerste keer worden medailles die al verdiend zijn stil toegekend,
    /// met hun oorspronkelijke datum, en volgt hooguit één samenvatting.
    func sync(in context: ModelContext) {
        let trades = (try? context.fetch(FetchDescriptor<Trade>())) ?? []
        // Bij elke terugkeer naar de app: niets opnieuw doorrekenen als de
        // trades niet veranderd zijn (aantal + laatste wijziging).
        let fingerprint = WidgetComputationCache.version(for: trades)
        guard fingerprint != lastSyncFingerprint else { return }
        lastSyncFingerprint = fingerprint
        sync(trades: trades)
    }

    func sync(trades: [Trade]) {
        let evaluation = service.evaluate(trades)
        self.evaluation = evaluation
        let newIDs = store.record(evaluation.achievedDates)

        guard store.hasCompletedInitialSync else {
            store.markInitialSyncDone()
            if !newIDs.isEmpty {
                enqueue([.summary(count: newIDs.count, isInitial: true)])
            }
            return
        }
        announce(newIDs)
    }

    // MARK: - Trade opgeslagen

    /// Na het opslaan in het tradeformulier: animatie (alleen bij een nieuwe
    /// trade), doorsturen naar Rapporten en nieuwe medailles.
    func tradeSaved(_ trade: Trade, isNew: Bool, in context: ModelContext) {
        let trades = (try? context.fetch(FetchDescriptor<Trade>())) ?? []

        if isNew {
            if settings.animationsEnabled {
                celebration = makeCelebration(for: trade, allTrades: trades)
            } else if settings.openReportsAfterSave {
                requestedTab = .reports
            }
        }
        sync(trades: trades)
    }

    /// De animatie is klaar (of overgeslagen met een tik).
    func finishCelebration() {
        guard celebration != nil else { return }
        celebration = nil
        if settings.openReportsAfterSave {
            requestedTab = .reports
        }
        showNextToastIfIdle()
    }

    private func makeCelebration(for trade: Trade, allTrades: [Trade]) -> Celebration {
        let metrics = statsService.metrics(for: trade)
        var streak = 0
        if metrics.outcome == .win {
            let stats = statsService.statistics(for: allTrades)
            if stats.currentStreakIsWinning == true {
                streak = stats.currentStreak
            }
            // De trade zelf is een winst: minimaal 1, ook als hij met een
            // oudere datum is gelogd.
            streak = max(streak, 1)
        }
        return Celebration(
            outcome: metrics.outcome,
            netPnL: metrics.netPnL,
            currency: trade.account?.currency ?? "USD",
            winStreak: streak
        )
    }

    // MARK: - Meldingen

    private func announce(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let definitions = ids
            .compactMap { MedalCatalog.definition(withID: $0) }
            .sorted { lhs, rhs in
                (store.unlocked[lhs.id] ?? .distantPast, lhs.tier) < (store.unlocked[rhs.id] ?? .distantPast, rhs.tier)
            }
        if definitions.count > Self.maximumIndividualToasts {
            enqueue([.summary(count: definitions.count, isInitial: false)])
        } else {
            enqueue(definitions.map { .medal($0, store.unlocked[$0.id] ?? Date()) })
        }
    }

    private func enqueue(_ toasts: [Toast]) {
        guard settings.medalNotificationsEnabled else { return }
        queue.append(contentsOf: toasts)
        showNextToastIfIdle()
    }

    /// Toont de volgende melding, maar niet tijdens de animatie.
    private func showNextToastIfIdle() {
        guard currentToast == nil, celebration == nil, !queue.isEmpty else { return }
        currentToast = queue.removeFirst()
    }

    /// Melding weg (na de tijd, of weggeveegd); de volgende komt na een korte pauze.
    func dismissToast() {
        guard currentToast != nil else { return }
        currentToast = nil
        guard !queue.isEmpty else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.showNextToastIfIdle()
        }
    }

    /// Tik op een melding: overzicht openen, met de medaille uitgelicht.
    func openToast() {
        if case .medal(let definition, _) = currentToast {
            highlightedMedalID = definition.id
        } else {
            highlightedMedalID = nil
        }
        queue.removeAll()
        currentToast = nil
        isOverviewPresented = true
    }

    /// Medaille-knop (dashboard): overzicht openen.
    func openOverview() {
        highlightedMedalID = nil
        isOverviewPresented = true
    }
}
