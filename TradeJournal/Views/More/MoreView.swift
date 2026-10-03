import SwiftUI
import SwiftData

/// "Meer"-tab: instellingen en beheer, compact in inklapbare secties.
///
/// - Overzicht: aantallen in één rij.
/// - Account & beveiliging: accounts met doelen/limieten, app-slot.
/// - Trading: confluences, screenshot-templates.
/// - Journal: progress tracker, notebook en journal-templates.
/// - Weergave & thema: thema (editor in een sheet), animaties, rondleiding.
/// - Meldingen & rewards: medailles, medaillemeldingen, na opslaan naar
///   Rapporten, herinneringen en live koers.
/// - Data: backup & herstel (incl. automatische backup en CSV-export) en
///   CSV-import.
/// - Debug-tools uit fase 1: standaarddata seeden, ~2 jaar voorbeelddata
///   genereren en alle data wissen (standaard ingeklapt).
struct MoreView: View {

    @Environment(\.modelContext) private var modelContext

    @Query private var accounts: [Account]
    @Query private var trades: [Trade]
    @Query private var confluences: [Confluence]
    @Query private var instruments: [Instrument]

    @Environment(AppLockViewModel.self) private var appLock
    @Environment(OnboardingViewModel.self) private var onboarding
    @Environment(RewardsViewModel.self) private var rewards

    @AppStorage(BackupSettings.Keys.lastBackupDate) private var lastBackupInterval: Double = 0
    @AppStorage(BackupSettings.Keys.reminderDismissed) private var isReminderDismissed = false
    @AppStorage(RewardSettings.Keys.animationsEnabled) private var animationsEnabled = true
    @AppStorage(RewardSettings.Keys.medalNotificationsEnabled) private var medalNotificationsEnabled = true
    @AppStorage(RewardSettings.Keys.openReportsAfterSave) private var openReportsAfterSave = true
    @AppStorage(ReminderSettings.Keys.isEnabled) private var reminderEnabled = false
    @AppStorage(LiveQuoteSettings.Keys.isEnabled) private var liveQuoteEnabled = true
    @AppStorage(AppLockService.Keys.isEnabled) private var appLockEnabled = false
    /// Ingeklapte secties (komma-gescheiden id's); alleen een weergavevoorkeur.
    @AppStorage("more.collapsedSections") private var collapsedSections = SettingsSection.debug.rawValue

    @State private var isBusy = false
    @State private var showingCSVImport = false
    @State private var showingMT5Import = false
    @State private var confirmWipe = false
    @State private var lastMessage: String? = nil

    /// Secties van het instellingenscherm (ook de sleutel voor in/uitklappen).
    private enum SettingsSection: String {
        case account, trading, journal, appearance, rewards, data, debug

        var title: String {
            switch self {
            case .account: return "Account & beveiliging"
            case .trading: return "Trading"
            case .journal: return "Journal"
            case .appearance: return "Weergave & thema"
            case .rewards: return "Meldingen & rewards"
            case .data: return "Data"
            case .debug: return "Debug (fase 1)"
            }
        }

        var systemImage: String {
            switch self {
            case .account: return "person.crop.circle"
            case .trading: return "chart.xyaxis.line"
            case .journal: return "book"
            case .appearance: return "paintpalette"
            case .rewards: return "rosette"
            case .data: return "externaldrive"
            case .debug: return "ladybug"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                List {
                    overviewSection

                    collapsible(.account) {
                        link("Accounts & doelen", systemImage: "person.2", value: "\(accounts.count)") { AccountsView() }
                        link("App-slot", systemImage: "lock", value: onOff(appLockEnabled)) { AppLockSettingsView(viewModel: appLock) }
                    }

                    collapsible(.trading) {
                        link("Confluences", systemImage: "checklist", value: "\(confluences.count)") { ConfluencesView() }
                        link("Screenshot-templates", systemImage: "text.viewfinder") { ScreenshotTemplatesView() }
                    }

                    collapsible(.journal) {
                        link("Progress tracker", systemImage: "flame") { ProgressTrackerView() }
                        link("Notebook", systemImage: "note.text") { NotebookView() }
                        link("Journal-templates", systemImage: "doc.text") { JournalTemplatesView() }
                    }

                    collapsible(.appearance) {
                        link(AppStrings.Themes.settingsTitle, systemImage: "paintpalette", value: ThemeStore.shared.palette.name) { ThemeSettingsView() }
                        toggle("Animaties", systemImage: "sparkles.rectangle.stack", isOn: $animationsEnabled,
                               tip: "Succesanimatie en hot streak na het opslaan van een nieuwe trade. Met 'Verminder beweging' (iOS) wordt het een korte fade.")
                        Button {
                            onboarding.startTour()
                        } label: {
                            Label(AppStrings.Settings.replayTour, systemImage: "sparkles")
                        }
                    }

                    collapsible(.rewards) {
                        link(AppStrings.Rewards.medalsTitle, systemImage: "rosette", value: "\(rewards.unlockedCount)/\(rewards.totalCount)") { MedalsView() }
                        toggle("Medaillemeldingen", systemImage: "bell.badge", isOn: $medalNotificationsEnabled,
                               tip: "Korte melding bovenin als je een medaille behaalt. Medailles worden altijd bijgehouden, ook als dit uit staat.")
                        toggle("Na opslaan naar Rapporten", systemImage: "chart.bar.doc.horizontal", isOn: $openReportsAfterSave,
                               tip: "Ga na het opslaan van een nieuwe trade automatisch naar de Rapporten-tab.")
                        link("Herinneringen", systemImage: "bell", value: onOff(reminderEnabled)) { ReminderSettingsView() }
                        link("Live koers", systemImage: "dot.radiowaves.left.and.right", value: onOff(liveQuoteEnabled)) { LiveQuoteSettingsView() }
                    }

                    collapsible(.data) {
                        NavigationLink {
                            BackupView()
                        } label: {
                            HStack {
                                Label("Backup & herstel", systemImage: "externaldrive")
                                Spacer()
                                if isBackupStale {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Theme.warning)
                                }
                            }
                        }

                        Button {
                            showingCSVImport = true
                        } label: {
                            Label("CSV importeren", systemImage: "square.and.arrow.down.on.square")
                        }

                        Button {
                            showingMT5Import = true
                        } label: {
                            Label("MT5-screenshots importeren", systemImage: "text.viewfinder")
                        }
                    }

                    collapsible(.debug) {
                        Button {
                            perform { SeedService.seedDefaultsIfNeeded(in: modelContext) }
                            lastMessage = "Standaarddata ingeschoten (confluences alleen als er nog geen enkele is)."
                        } label: {
                            Label("Standaarddata inschieten", systemImage: "square.and.arrow.down")
                        }
                        .disabled(isBusy)

                        Button {
                            perform {
                                let count = SampleDataService.generate(in: modelContext)
                                lastMessage = "\(count) voorbeeldtrades toegevoegd."
                            }
                        } label: {
                            Label("Voorbeelddata genereren (~2 jaar)", systemImage: "wand.and.stars")
                        }
                        .disabled(isBusy)

                        Button(role: .destructive) {
                            confirmWipe = true
                        } label: {
                            Label("Alles wissen", systemImage: "trash")
                        }
                        .disabled(isBusy)
                    }
                }
                .listSectionSpacing(.compact)
                .environment(\.defaultMinListRowHeight, 40)
                .scrollContentBackground(.hidden)
                .background(Theme.background)

                if isBusy {
                    ProgressView("Bezig…")
                        .padding(Theme.cardPadding)
                        .background(Theme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                }
            }
            .navigationTitle("Meer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showingCSVImport) {
                CSVImportView()
            }
            .sheet(isPresented: $showingMT5Import) {
                MT5ImportView()
            }
            // Resultaat van een debug-actie als pop-up: onderaan de lijst viel
            // de melding buiten beeld.
            .alert(
                lastMessage ?? "",
                isPresented: Binding(get: { lastMessage != nil }, set: { if !$0 { lastMessage = nil } })
            ) {
                Button("OK", role: .cancel) { lastMessage = nil }
            }
            .confirmationDialog(
                "Weet je zeker dat je alle data wilt wissen?",
                isPresented: $confirmWipe,
                titleVisibility: .visible
            ) {
                Button("Wissen", role: .destructive) {
                    perform {
                        SampleDataService.wipeAll(in: modelContext)
                        lastMessage = "Alle data is gewist."
                    }
                }
                Button("Annuleren", role: .cancel) { }
            } message: {
                Text("Deze actie kan niet ongedaan gemaakt worden.")
            }
        }
    }

    // MARK: - Overzicht

    /// Aantallen in één compacte rij i.p.v. vier losse rijen.
    private var overviewSection: some View {
        Section {
            HStack(spacing: 0) {
                counter("Accounts", accounts.count)
                counter("Trades", trades.count)
                counter("Confluences", confluences.count)
                counter("Instrumenten", instruments.count)
            }
            .padding(.vertical, 2)
        }
        .listRowBackground(Theme.card)
    }

    private func counter(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Bouwstenen

    /// Sectie met een tikbare kop die de inhoud in- en uitklapt.
    private func collapsible<Content: View>(_ section: SettingsSection, @ViewBuilder content: () -> Content) -> some View {
        let expanded = isExpanded(section)
        let rows = content()
        return Section {
            if expanded {
                rows
            }
        } header: {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { toggleExpanded(section) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: section.systemImage)
                        .font(.caption)
                    Text(section.title)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .foregroundStyle(Theme.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Uitgeklapt" : "Ingeklapt")
        }
        .listRowBackground(Theme.card)
    }

    private func link<Destination: View>(_ title: String, systemImage: String, value: String? = nil, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if let value {
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
    }

    private func toggle(_ title: String, systemImage: String, isOn: Binding<Bool>, tip: String) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                InfoTipButton(text: tip)
            }
        }
        .tint(Theme.accent)
    }

    private func onOff(_ value: Bool) -> String { value ? "Aan" : "Uit" }

    private func isExpanded(_ section: SettingsSection) -> Bool {
        !collapsedSections.split(separator: ",").contains(Substring(section.rawValue))
    }

    private func toggleExpanded(_ section: SettingsSection) {
        var collapsed = Set(collapsedSections.split(separator: ",").map(String.init))
        if collapsed.contains(section.rawValue) {
            collapsed.remove(section.rawValue)
        } else {
            collapsed.insert(section.rawValue)
        }
        collapsedSections = collapsed.sorted().joined(separator: ",")
    }

    private var isBackupStale: Bool {
        BackupSettings.shouldShowReminder(
            lastBackup: lastBackupInterval > 0 ? Date(timeIntervalSince1970: lastBackupInterval) : nil,
            dismissed: isReminderDismissed
        )
    }

    private func perform(_ work: @escaping () -> Void) {
        isBusy = true
        DispatchQueue.main.async {
            work()
            isBusy = false
        }
    }
}

#Preview {
    MoreView()
        .environment(AppLockViewModel())
        .environment(OnboardingViewModel())
        .environment(RewardsViewModel())
        .modelContainer(for: AppSchema.models, inMemory: true)
        .preferredColorScheme(.dark)
}
