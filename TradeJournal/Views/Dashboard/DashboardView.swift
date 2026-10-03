import SwiftUI
import SwiftData

/// Navigatiedoel: dagdetail vanuit een widget (bijv. een stip in de jaar-heatmap).
struct DashboardDayRoute: Hashable {
    let date: Date
}

/// Dashboard-tab: aanpasbaar dashboard met widgets.
///
/// Bovenaan blijven live koers, backup-waarschuwing en limietwaarschuwing
/// staan; daaronder de tabbladen (meerdere dashboards), de filters van het
/// geopende dashboard en het widgetraster (klein = halve breedte, groot =
/// volle breedte). In de bewerkmodus: widgets toevoegen uit de bibliotheek,
/// verwijderen, slepen om te herordenen, van grootte wisselen en instellen.
///
/// Alle mutaties lopen via `DashboardLayoutViewModel` → `DashboardLayoutService`;
/// cijfers via `DashboardViewModel`/`WidgetDataService` (dus `StatsService`).
struct DashboardView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Trade.entryDate, order: .reverse) private var trades: [Trade]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \Playbook.name) private var playbooks: [Playbook]
    @Query(sort: \Confluence.sortOrder) private var confluences: [Confluence]
    @Query(sort: \Dashboard.sortOrder) private var dashboards: [Dashboard]
    @Query(sort: \DailyRule.sortOrder) private var rules: [DailyRule]
    @Query(sort: \DailyJournal.date) private var journals: [DailyJournal]
    @Query private var ruleChecks: [DailyRuleCheck]

    /// Filters van het geopende dashboard (+ grafiekdata, doelen, score).
    @State private var viewModel = DashboardViewModel()
    @State private var layout = DashboardLayoutViewModel()
    @State private var liveQuote = LiveQuoteViewModel()
    @State private var cache = WidgetComputationCache()
    @State private var path = NavigationPath()

    /// Dashboard waarvan de filters in `viewModel` staan.
    @State private var loadedDashboardID: UUID?
    @State private var showingLibrary = false
    @State private var settingsWidget: DashboardWidget?
    @State private var widgetToDelete: DashboardWidget?
    @State private var dropTargetID: UUID?
    @State private var showingNewDashboard = false
    @State private var dashboardToRename: Dashboard?
    @State private var dashboardToDelete: Dashboard?
    @State private var nameDraft = ""
    @State private var confirmReset = false

    @Environment(\.scenePhase) private var scenePhase
    @Environment(RewardsViewModel.self) private var rewards
    @AppStorage(LiveQuoteSettings.Keys.isEnabled) private var liveQuoteEnabled = true
    @AppStorage(LiveQuoteSettings.Keys.symbolOverride) private var liveQuoteSymbolOverride = ""

    private let dataService = WidgetDataService()

    private var currentDashboard: Dashboard? {
        layout.selectedDashboard(in: dashboards)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.background.ignoresSafeArea()

                if trades.isEmpty && !layout.isEditing {
                    PlaceholderView(
                        title: "Dashboard",
                        systemImage: "chart.line.uptrend.xyaxis",
                        subtitle: "Netto P&L, win rate, profit factor en trading score verschijnen hier zodra je trades hebt gelogd."
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if liveQuoteEnabled, liveQuote.symbol != nil {
                                LiveQuoteCardView(viewModel: liveQuote)
                            }

                            BackupReminderBannerView()

                            let goals = viewModel.goalStatuses(accounts: accounts, trades: trades)
                            GoalWarningBannerView(statuses: goals)

                            if dashboards.count > 1 || layout.isEditing {
                                DashboardTabsBar(
                                    dashboards: dashboards,
                                    selectedID: currentDashboard?.id,
                                    isEditing: layout.isEditing,
                                    onSelect: { layout.select($0) },
                                    onAdd: { startNewDashboard() },
                                    onRename: { startRename($0) },
                                    onMove: { dashboard, offset in layout.move(dashboard, by: offset, in: modelContext) },
                                    onDelete: { dashboardToDelete = $0 }
                                )
                            }

                            DashboardFilterBar(
                                viewModel: viewModel,
                                accounts: accounts,
                                symbols: viewModel.availableSymbols(from: trades),
                                playbooks: playbooks,
                                confluences: confluences
                            )

                            if layout.isEditing {
                                editActions
                            }

                            if let dashboard = currentDashboard {
                                widgetGrid(dashboard)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle(currentDashboard.map { dashboards.count > 1 ? $0.name : "Dashboard" } ?? "Dashboard")
            .toolbar {
                // Woordmerk klein boven de grote titel.
                ToolbarItem(placement: .topBarLeading) {
                    Daytr8LogoView(variant: .wordmark, size: 20)
                }
                // Medaille-overzicht.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        rewards.openOverview()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "rosette")
                            Text("\(rewards.unlockedCount)")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                    .accessibilityLabel(AppStrings.Rewards.openMedalsAccessibility)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(layout.isEditing ? "Gereed" : "Bewerk") {
                        withAnimation(.easeInOut(duration: 0.2)) { layout.isEditing.toggle() }
                    }
                    .fontWeight(layout.isEditing ? .semibold : .regular)
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: Trade.self) { trade in
                TradeDetailView(trade: trade)
            }
            .navigationDestination(for: DashboardDayRoute.self) { route in
                DayDetailView(date: route.date)
            }
            // Filters horen bij het geopende dashboard.
            .onChange(of: viewModel.filterState) { _, state in
                guard let dashboard = currentDashboard, loadedDashboardID == dashboard.id else { return }
                layout.saveFilters(state, for: dashboard, in: modelContext)
            }
            .onChange(of: currentDashboard?.id) { _, _ in loadFiltersIfNeeded() }
            // Live koers: alleen pollen als de app actief is én het dashboard
            // zichtbaar is; op de achtergrond of in een andere tab stopt het.
            .onAppear {
                layout.ensureDefault(in: modelContext)
                loadFiltersIfNeeded()
                liveQuote.update(trades: trades)
                updateLiveQuotePolling()
            }
            .onDisappear { liveQuote.stop() }
            .onChange(of: scenePhase) { _, _ in updateLiveQuotePolling() }
            .onChange(of: LiveQuoteViewModel.symbol(for: trades, override: liveQuoteSymbolOverride)) { _, _ in
                liveQuote.update(trades: trades)
                updateLiveQuotePolling()
            }
            .onChange(of: liveQuoteEnabled) { _, _ in updateLiveQuotePolling() }
            .task {
                // Alleen met geladen data opruimen; een lege store wist geen bewaarde filters.
                guard !trades.isEmpty else { return }
                viewModel.pruneFilters(
                    accountIDs: Set(accounts.map(\.id)),
                    playbookIDs: Set(playbooks.map(\.id)),
                    confluenceIDs: Set(confluences.map(\.id))
                )
            }
            .sheet(isPresented: $showingLibrary) {
                WidgetLibraryView(
                    previewContext: { previewContext(for: $0) },
                    onAdd: { definition in
                        guard let dashboard = currentDashboard else { return }
                        layout.addWidget(definition.type, size: definition.defaultSize, settings: definition.defaultSettings, to: dashboard, in: modelContext)
                    }
                )
            }
            .sheet(item: $settingsWidget) { widget in
                if let definition = DashboardWidgetRegistry.definition(for: widget) {
                    WidgetSettingsSheetView(
                        definition: definition,
                        accounts: accounts,
                        initialSettings: widget.settings,
                        initialSize: widget.size,
                        onSave: { settings, size in layout.update(widget, settings: settings, size: size, in: modelContext) },
                        onDelete: { layout.removeWidget(widget, in: modelContext) }
                    )
                }
            }
            .confirmationDialog("Widget verwijderen?", isPresented: isPresent($widgetToDelete), titleVisibility: .visible) {
                Button("Verwijderen", role: .destructive) {
                    if let widget = widgetToDelete { layout.removeWidget(widget, in: modelContext) }
                    widgetToDelete = nil
                }
                Button("Annuleren", role: .cancel) { widgetToDelete = nil }
            }
            .confirmationDialog("Standaardindeling herstellen?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Herstel standaardindeling", role: .destructive) {
                    if let dashboard = currentDashboard { layout.resetToDefault(dashboard, in: modelContext) }
                }
                Button("Annuleren", role: .cancel) { }
            } message: {
                Text("De widgets van dit dashboard worden vervangen door de standaardindeling. Je trades en de filters blijven staan.")
            }
            .confirmationDialog("Dashboard verwijderen?", isPresented: isPresent($dashboardToDelete), titleVisibility: .visible) {
                Button("Verwijderen", role: .destructive) {
                    if let dashboard = dashboardToDelete { layout.delete(dashboard, in: modelContext) }
                    dashboardToDelete = nil
                }
                Button("Annuleren", role: .cancel) { dashboardToDelete = nil }
            } message: {
                Text("Het dashboard en zijn widgets worden verwijderd. Je trades blijven staan.")
            }
            .alert("Nieuw dashboard", isPresented: $showingNewDashboard) {
                TextField("Naam, bijv. Prop firm", text: $nameDraft)
                Button("Aanmaken") {
                    layout.addDashboard(named: nameDraft, in: modelContext)
                }
                Button("Annuleren", role: .cancel) { }
            } message: {
                Text("Een nieuw dashboard begint leeg; voeg daarna widgets toe.")
            }
            .alert("Dashboard hernoemen", isPresented: isPresent($dashboardToRename)) {
                TextField("Naam", text: $nameDraft)
                Button("Bewaar") {
                    if let dashboard = dashboardToRename { layout.rename(dashboard, to: nameDraft, in: modelContext) }
                    dashboardToRename = nil
                }
                Button("Annuleren", role: .cancel) { dashboardToRename = nil }
            }
        }
    }

    // MARK: - Bewerkmodus

    private var editActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    showingLibrary = true
                } label: {
                    Label("Widget toevoegen", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(Theme.onAccent)
                        .background(Theme.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Menu {
                    Button { startNewDashboard() } label: { Label("Nieuw dashboard", systemImage: "plus.rectangle.on.rectangle") }
                    if let dashboard = currentDashboard {
                        Button { startRename(dashboard) } label: { Label("Dashboard hernoemen", systemImage: "pencil") }
                        Button(role: .destructive) { confirmReset = true } label: {
                            Label("Herstel standaardindeling", systemImage: "arrow.counterclockwise")
                        }
                        if dashboards.count > 1 {
                            Button(role: .destructive) { dashboardToDelete = dashboard } label: {
                                Label("Dashboard verwijderen", systemImage: "trash")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("Meer dashboardopties")
            }
            Text("Houd een widget vast en sleep hem naar een andere plek. Filters hierboven gelden voor dit dashboard.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Widgetraster

    private func widgetGrid(_ dashboard: Dashboard) -> some View {
        let widgets = dashboard.sortedWidgets.filter { layout.isEditing || DashboardWidgetRegistry.definition(for: $0) != nil }
        let sizes = widgets.map { widget in
            DashboardWidgetRegistry.definition(for: widget)?.effectiveSize(widget.size) ?? .large
        }
        let rows = DashboardLayoutService.rows(for: sizes)
        let version = cacheVersion
        let filterKey = String(describing: viewModel.filterState)

        return VStack(spacing: Theme.widgetSpacing) {
            if widgets.isEmpty {
                emptyDashboard
            }
            ForEach(rows, id: \.self) { row in
                let rowWidgets = row.map { widgets[$0] }
                let isHalfRow = row.count == 1 && sizes[row[0]] == .small
                HStack(alignment: .top, spacing: Theme.widgetSpacing) {
                    ForEach(rowWidgets) { widget in
                        widgetCard(widget, in: dashboard, version: version, filterKey: filterKey)
                    }
                    if isHalfRow {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
                .fixedSize(horizontal: false, vertical: row.count > 1)
                .id(rowWidgets.map(\.id))
            }
        }
    }

    private var emptyDashboard: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.title)
                .foregroundStyle(Theme.accent)
            Text("Dit dashboard is nog leeg")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Button("Widget toevoegen") {
                layout.isEditing = true
                showingLibrary = true
            }
            .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.cardPadding)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func widgetCard(_ widget: DashboardWidget, in dashboard: Dashboard, version: String, filterKey: String) -> some View {
        if let definition = DashboardWidgetRegistry.definition(for: widget) {
            let settings = widget.settings
            let size = definition.effectiveSize(widget.size)
            let context = renderContext(widgetID: widget.id, size: size, settings: settings, version: version, filterKey: filterKey) {
                settingsWidget = widget
            }
            WidgetContainerView(
                title: definition.displayTitle(for: settings),
                systemImage: definition.systemImage,
                subtitle: definition.subtitle(for: settings),
                content: definition.makeContent(context),
                isEditing: layout.isEditing,
                canToggleSize: definition.supportedSizes.count > 1,
                size: size,
                onToggleSize: { layout.toggleSize(of: widget, in: modelContext) },
                onSettings: { settingsWidget = widget },
                onDelete: { widgetToDelete = widget },
                onMoveUp: { layout.moveWidget(widget, by: -1, in: modelContext) },
                onMoveDown: { layout.moveWidget(widget, by: 1, in: modelContext) }
            )
            .modifier(reorderModifier(for: widget, in: dashboard))
        } else {
            // Type uit een nieuwere app-versie: alleen in de bewerkmodus zichtbaar, om te verwijderen.
            WidgetContainerView(
                title: "Onbekende widget",
                systemImage: "questionmark.square.dashed",
                content: AnyView(WidgetEmptyStateView(text: "Deze widget komt uit een nieuwere versie van de app.")),
                isEditing: true,
                canToggleSize: false,
                onSettings: { },
                onDelete: { widgetToDelete = widget },
                onMoveUp: { layout.moveWidget(widget, by: -1, in: modelContext) },
                onMoveDown: { layout.moveWidget(widget, by: 1, in: modelContext) }
            )
        }
    }

    private func reorderModifier(for widget: DashboardWidget, in dashboard: Dashboard) -> WidgetReorderModifier {
        WidgetReorderModifier(
            isEnabled: layout.isEditing,
            widgetID: widget.id,
            isTargeted: dropTargetID == widget.id,
            onDrop: { droppedID in
                withAnimation(.easeInOut(duration: 0.2)) {
                    layout.drop(widgetID: droppedID, onto: widget, in: dashboard, context: modelContext)
                }
            },
            onTargetChange: { targeted in
                if targeted {
                    dropTargetID = widget.id
                } else if dropTargetID == widget.id {
                    dropTargetID = nil
                }
            }
        )
    }

    // MARK: - Context voor widgets

    /// Versie van de data waar widgets op rekenen; verandert zodra trades,
    /// accountdoelen, regels of journals wijzigen (dan wordt de cache geleegd).
    private var cacheVersion: String {
        let accountKey = accounts.map { account in
            "\(account.id)\(account.typeRaw)\(account.currency)\(account.startingBalance)\(account.monthlyProfitTarget ?? -1)\(account.dailyLossLimit ?? -1)\(account.maxDrawdown ?? -1)"
        }.joined(separator: ",")
        let journalStamp = journals.reduce(0.0) { max($0, $1.updatedAt.timeIntervalSince1970) }
        let ruleKey = rules.map { "\($0.id)\($0.isActive)\($0.threshold)\($0.kindRaw)" }.joined(separator: ",")
        let checksKey = "\(ruleChecks.count)-\(ruleChecks.filter(\.isFollowed).count)"
        return WidgetComputationCache.version(for: trades, extra: "\(accountKey)|\(journals.count)-\(journalStamp)|\(ruleKey)|\(checksKey)")
    }

    private func renderContext(
        widgetID: UUID,
        size: WidgetSize,
        settings: WidgetSettings,
        version: String,
        filterKey: String,
        isPreview: Bool = false,
        onEdit: @escaping () -> Void
    ) -> WidgetRenderContext {
        WidgetRenderContext(
            widgetID: widgetID,
            size: size,
            settings: settings,
            allTrades: trades,
            accounts: accounts,
            rules: rules,
            journals: journals,
            ruleChecks: ruleChecks,
            baseFilter: viewModel.filterState,
            baseFilterKey: filterKey,
            dashboardModel: viewModel,
            dataService: dataService,
            cache: cache,
            cacheVersion: version,
            isPreview: isPreview,
            onOpenDay: { day in path.append(DashboardDayRoute(date: day)) },
            onEditSettings: onEdit
        )
    }

    /// Voorbeeld in de bibliotheek: standaardinstellingen, eigen data.
    private func previewContext(for definition: any DashboardWidgetDefinition) -> WidgetRenderContext {
        let index = DashboardWidgetType.allCases.firstIndex(of: definition.type) ?? 0
        let previewID = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index)) ?? UUID()
        return renderContext(
            widgetID: previewID,
            size: definition.defaultSize,
            settings: definition.defaultSettings,
            version: cacheVersion,
            filterKey: String(describing: viewModel.filterState),
            isPreview: true,
            onEdit: { }
        )
    }

    // MARK: - Helpers

    private func loadFiltersIfNeeded() {
        guard let dashboard = currentDashboard, dashboard.id != loadedDashboardID else { return }
        loadedDashboardID = dashboard.id
        viewModel.apply(dashboard.filters)
    }

    private func startNewDashboard() {
        nameDraft = ""
        showingNewDashboard = true
    }

    private func startRename(_ dashboard: Dashboard) {
        nameDraft = dashboard.name
        dashboardToRename = dashboard
    }

    private func isPresent<T>(_ binding: Binding<T?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
    }

    private func updateLiveQuotePolling() {
        if scenePhase == .active, liveQuoteEnabled {
            liveQuote.start()
        } else {
            liveQuote.stop()
        }
    }
}

/// Slepen en neerzetten van widgets, alleen in de bewerkmodus.
struct WidgetReorderModifier: ViewModifier {
    let isEnabled: Bool
    let widgetID: UUID
    let isTargeted: Bool
    let onDrop: (String) -> Void
    let onTargetChange: (Bool) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .stroke(Theme.accent, lineWidth: isTargeted ? 2 : 0)
                )
                .draggable(widgetID.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    guard let first = items.first else { return false }
                    onDrop(first)
                    return true
                } isTargeted: { targeted in
                    onTargetChange(targeted)
                }
        } else {
            content
        }
    }
}

#Preview {
    DashboardView()
        .environment(RewardsViewModel())
        .modelContainer(for: AppSchema.models, inMemory: true)
        .preferredColorScheme(.dark)
}
