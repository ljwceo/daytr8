import SwiftUI

/// De standaardsecties van het instellingenscherm van een widget: periode,
/// account(s), kengetal, heatmap-kleur, dimensie en aantal — alleen de
/// secties uit `options`.
struct StandardWidgetSettingsSections: View {

    @Binding var settings: WidgetSettings
    let options: WidgetSettingsOptions
    let accounts: [Account]

    var body: some View {
        if options.contains(.metric) {
            Section("Kengetal") {
                Picker("Toon", selection: $settings.metric) {
                    ForEach(WidgetSettings.Metric.allCases) { metric in
                        Text(metric.displayName).tag(metric)
                    }
                }
            }
            .listRowBackground(Theme.card)
        }

        if options.contains(.heatmapMetric) {
            Section {
                Picker("Kleur toont", selection: $settings.heatmapMetric) {
                    ForEach(WidgetSettings.HeatmapMetric.allCases) { metric in
                        Text(metric.displayName).tag(metric)
                    }
                }
            } header: {
                Text("Heatmap")
            } footer: {
                Text("Behaalde R telt alleen trades met een stop loss of gepland risico.")
            }
            .listRowBackground(Theme.card)
        }

        if options.contains(.dimension) {
            Section("Indeling") {
                Picker("Per", selection: $settings.dimension) {
                    ForEach(WidgetSettings.Dimension.allCases) { dimension in
                        Text(dimension.displayName).tag(dimension)
                    }
                }
            }
            .listRowBackground(Theme.card)
        }

        if options.contains(.itemCount) {
            Section("Aantal") {
                Stepper(value: $settings.itemCount, in: 1...10) {
                    Text("\(settings.itemCount) regels")
                }
            }
            .listRowBackground(Theme.card)
        }

        if options.contains(.period) {
            Section {
                Picker("Periode", selection: $settings.period) {
                    ForEach(WidgetSettings.Period.allCases) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                if settings.period == .custom {
                    DatePicker("Van", selection: customStart, displayedComponents: .date)
                    DatePicker("Tot en met", selection: customEnd, in: customStart.wrappedValue..., displayedComponents: .date)
                }
            } header: {
                Text("Periode")
            } footer: {
                Text("Statistiekkaarten vergelijken met de periode ervoor (vorige week, maand, jaar of een even lange periode).")
            }
            .listRowBackground(Theme.card)
        }

        if options.contains(.accounts), !accounts.isEmpty {
            Section {
                ForEach(accounts) { account in
                    Toggle(isOn: accountBinding(account)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name).foregroundStyle(Theme.textPrimary)
                            Text(account.type.displayName).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .tint(Theme.accent)
                }
            } header: {
                Text("Accounts")
            } footer: {
                Text("Niets aangevinkt = de accountfilter van het dashboard.")
            }
            .listRowBackground(Theme.card)
        }
    }

    private var customStart: Binding<Date> {
        Binding(
            get: { settings.customStart ?? Calendar.current.startOfDay(for: Date()) },
            set: { newValue in
                settings.customStart = Calendar.current.startOfDay(for: newValue)
                if let end = settings.customEnd, end < newValue { settings.customEnd = endOfDay(newValue) }
            }
        )
    }

    private var customEnd: Binding<Date> {
        Binding(
            get: { settings.customEnd ?? endOfDay(Date()) },
            set: { settings.customEnd = endOfDay($0) }
        )
    }

    private func endOfDay(_ date: Date) -> Date {
        let start = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    private func accountBinding(_ account: Account) -> Binding<Bool> {
        Binding(
            get: { settings.accountIDs.contains(account.id) },
            set: { isOn in
                if isOn {
                    if !settings.accountIDs.contains(account.id) { settings.accountIDs.append(account.id) }
                } else {
                    settings.accountIDs.removeAll { $0 == account.id }
                }
            }
        )
    }
}

/// Sheet met de instellingen van één widget: titel, grootte, de secties van
/// het type en verwijderen. Wijzigingen worden pas bij "Gereed" bewaard.
struct WidgetSettingsSheetView: View {

    let definition: any DashboardWidgetDefinition
    let accounts: [Account]
    let initialSettings: WidgetSettings
    let initialSize: WidgetSize
    let onSave: (WidgetSettings, WidgetSize) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings = WidgetSettings()
    @State private var size = WidgetSize.small
    @State private var titleText = ""
    @State private var confirmDelete = false
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Weergave") {
                    TextField(definition.defaultTitle(for: settings), text: $titleText)
                    if definition.supportedSizes.count > 1 {
                        Picker("Grootte", selection: $size) {
                            ForEach(definition.supportedSizes) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                    }
                }
                .listRowBackground(Theme.card)

                definition.makeSettingsView($settings, accounts: accounts)

                Section {
                    Button("Widget verwijderen", role: .destructive) { confirmDelete = true }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(definition.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gereed") {
                        var result = settings
                        let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
                        result.customTitle = trimmed.isEmpty ? nil : trimmed
                        if result.period == .custom {
                            let calendar = Calendar.current
                            if result.customStart == nil { result.customStart = calendar.startOfDay(for: Date()) }
                            if result.customEnd == nil { result.customEnd = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: Date())) }
                        }
                        onSave(result, size)
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Widget verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Verwijderen", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Annuleren", role: .cancel) { }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                settings = initialSettings
                size = definition.effectiveSize(initialSize)
                titleText = initialSettings.customTitle ?? ""
            }
        }
        .presentationDetents([.medium, .large])
    }
}
