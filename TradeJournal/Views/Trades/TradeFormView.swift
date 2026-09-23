import Foundation
import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Slim tradeformulier: standaardwaarden uit de laatste trade, automatische
/// P&L/R-berekening (`TradeFormViewModel.livePreview`) en sessie-autodetectie.
/// Wordt zowel voor het aanmaken als bewerken van een trade gebruikt.
struct TradeFormView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: TradeFormViewModel
    @State private var photoSelection: [PhotosPickerItem] = []

    @Query(sort: \Instrument.sortOrder) private var instruments: [Instrument]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \Playbook.name) private var playbooks: [Playbook]
    @Query(sort: \Confluence.sortOrder) private var allConfluences: [Confluence]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \Mistake.name) private var mistakes: [Mistake]

    init(mode: TradeFormViewModel.Mode, lastTrade: Trade? = nil, fallbackAccount: Account? = nil, initialDate: Date? = nil) {
        _viewModel = State(initialValue: TradeFormViewModel(mode: mode, lastTrade: lastTrade, fallbackAccount: fallbackAccount, initialDate: initialDate))
    }

    /// Actieve confluences, plus reeds geselecteerde (ook als die inmiddels gearchiveerd is).
    private var selectableConfluences: [Confluence] {
        allConfluences.filter { $0.isActive || viewModel.isSelected($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                previewCard
                if !viewModel.missingFields.isEmpty {
                    missingFieldsSection
                }
                accountSection
                instrumentSection
                timingSection
                pricesSection
                costsSection
                playbookSection
                confluencesSection
                tagsAndMistakesSection
                reflectionSection
                screenshotsSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Opslaan") {
                        viewModel.save(in: modelContext)
                        dismiss()
                    }
                    .disabled(!viewModel.isValid)
                }
            }
        }
    }

    // MARK: - Live preview

    private var previewCard: some View {
        let metrics = viewModel.livePreview
        let currency = viewModel.values.account?.currency ?? "USD"
        return HStack {
            metricColumn(
                title: metrics.outcome == .open ? "Status" : "Netto P&L",
                value: metrics.outcome == .open ? "Open" : metrics.netPnL.formatted(.currency(code: currency)),
                color: Theme.color(forPnL: metrics.netPnL)
            )
            metricColumn(
                title: "R-multiple",
                value: metrics.rMultiple.map { String(format: "%.2fR", $0) } ?? "—",
                color: Theme.textPrimary
            )
            metricColumn(title: "Sessie", value: viewModel.detectedSession.displayName, color: Theme.textPrimary)
        }
        .padding(Theme.cardPadding)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private func metricColumn(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Secties

    private var missingFieldsSection: some View {
        Section {
            ForEach(viewModel.missingFields, id: \.self) { field in
                Label(field, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
        } header: {
            Text("Nog nodig om op te slaan")
        }
    }

    private var accountSection: some View {
        Section("Account") {
            Picker("Account", selection: $viewModel.values.account) {
                Text("Geen").tag(Optional<Account>.none)
                ForEach(accounts) { account in
                    Text(account.name).tag(Optional(account))
                }
            }
            Toggle("Backtest-trade", isOn: $viewModel.values.isBacktest)
        }
    }

    private var instrumentSection: some View {
        Section("Instrument") {
            Picker("Preset", selection: presetBinding) {
                Text("Handmatig").tag(Optional<Instrument>.none)
                ForEach(instruments) { instrument in
                    Text("\(instrument.symbol) — \(instrument.name)").tag(Optional(instrument))
                }
            }
            TextField("Symbool", text: $viewModel.values.symbol)
                .textInputAutocapitalization(.characters)
            numberRow("Tick size", value: $viewModel.values.tickSize)
            numberRow("Tick value ($)", value: $viewModel.values.tickValue)
        }
    }

    private var presetBinding: Binding<Instrument?> {
        Binding<Instrument?>(
            get: { viewModel.values.instrument },
            set: { newValue in
                if let newValue {
                    viewModel.applyInstrumentPreset(newValue)
                } else {
                    viewModel.values.instrument = nil
                }
            }
        )
    }

    private var timingSection: some View {
        Section("Richting & tijden") {
            Picker("Richting", selection: $viewModel.values.direction) {
                ForEach(TradeDirection.allCases) { direction in
                    Text(direction.displayName).tag(direction)
                }
            }
            .pickerStyle(.segmented)

            DatePicker("Entry", selection: $viewModel.values.entryDate)

            Toggle("Trade is gesloten", isOn: closedBinding)

            if viewModel.values.exitDate != nil {
                DatePicker("Exit", selection: exitDateBinding)
            }
        }
    }

    private var closedBinding: Binding<Bool> {
        Binding<Bool>(
            get: { viewModel.values.exitDate != nil },
            set: { isClosed in
                if isClosed {
                    viewModel.values.exitDate = max(viewModel.values.entryDate, Date())
                    if viewModel.values.exitPrice == nil {
                        viewModel.values.exitPrice = viewModel.values.entryPrice
                    }
                } else {
                    viewModel.values.exitDate = nil
                    viewModel.values.exitPrice = nil
                }
            }
        )
    }

    private var exitDateBinding: Binding<Date> {
        Binding<Date>(
            get: { viewModel.values.exitDate ?? Date() },
            set: { viewModel.values.exitDate = $0 }
        )
    }

    private var pricesSection: some View {
        Section("Prijzen & risk") {
            numberRow("Entry-prijs", value: $viewModel.values.entryPrice)
            if viewModel.values.exitDate != nil {
                numberRow("Exit-prijs", value: exitPriceBinding)
            }
            numberRow("Aantal contracten/lots", value: $viewModel.values.quantity)
            numberRow("Stop loss", value: optionalDoubleBinding(\.stopLoss))
            numberRow("Take profit", value: optionalDoubleBinding(\.takeProfit))
            numberRow("Geplande risk ($)", value: optionalDoubleBinding(\.plannedRisk))
            numberRow("MAE", value: optionalDoubleBinding(\.mae))
            numberRow("MFE", value: optionalDoubleBinding(\.mfe))
        }
    }

    private var exitPriceBinding: Binding<Double> {
        Binding<Double>(
            get: { viewModel.values.exitPrice ?? 0 },
            set: { viewModel.values.exitPrice = $0 }
        )
    }

    private func optionalDoubleBinding(_ keyPath: WritableKeyPath<TradeEditingService.FormValues, Double?>) -> Binding<Double> {
        Binding<Double>(
            get: { viewModel.values[keyPath: keyPath] ?? 0 },
            set: { newValue in
                viewModel.values[keyPath: keyPath] = newValue == 0 ? nil : newValue
            }
        )
    }

    private var costsSection: some View {
        Section("Kosten") {
            numberRow("Commissie", value: $viewModel.values.commission)
            numberRow("Fees", value: $viewModel.values.fees)
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            DecimalFieldView(title: title, value: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var playbookSection: some View {
        Section("Playbook") {
            Picker("Playbook", selection: playbookBinding) {
                Text("Geen").tag(Optional<Playbook>.none)
                ForEach(playbooks) { playbook in
                    Text(playbook.name).tag(Optional(playbook))
                }
            }
            if let playbook = viewModel.values.playbook, !playbook.rules.isEmpty {
                ForEach(playbook.rules.sorted { $0.sortOrder < $1.sortOrder }) { rule in
                    Toggle(rule.text, isOn: ruleBinding(rule))
                }
            }
        }
    }

    private var playbookBinding: Binding<Playbook?> {
        Binding<Playbook?>(
            get: { viewModel.values.playbook },
            set: { viewModel.applyPlaybook($0) }
        )
    }

    private func ruleBinding(_ rule: PlaybookRule) -> Binding<Bool> {
        Binding<Bool>(
            get: { viewModel.isRuleFollowed(rule) },
            set: { viewModel.setRule(rule, followed: $0) }
        )
    }

    private var confluencesSection: some View {
        Section("Confluences") {
            ForEach(ConfluenceCategory.allCases) { category in
                let items = selectableConfluences.filter { $0.category == category }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(category.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        FlowLayout(spacing: 8) {
                            ForEach(items) { confluence in
                                ChipView(
                                    title: confluence.name,
                                    systemImage: confluence.iconName,
                                    color: Color(hex: confluence.colorHex),
                                    isSelected: viewModel.isSelected(confluence)
                                ) {
                                    viewModel.toggle(confluence)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Theme.card)
                }
            }
        }
    }

    private var tagsAndMistakesSection: some View {
        Section("Tags & fouten") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tags")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                FlowLayout(spacing: 8) {
                    ForEach(tags) { tag in
                        ChipView(title: tag.name, color: Color(hex: tag.colorHex), isSelected: viewModel.isSelected(tag)) {
                            viewModel.toggle(tag)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(Theme.card)

            VStack(alignment: .leading, spacing: 6) {
                Text("Fouten")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                FlowLayout(spacing: 8) {
                    ForEach(mistakes) { mistake in
                        ChipView(title: mistake.name, systemImage: "exclamationmark.triangle", color: Color(hex: mistake.colorHex), isSelected: viewModel.isSelected(mistake)) {
                            viewModel.toggle(mistake)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(Theme.card)
        }
    }

    private var reflectionSection: some View {
        Section("Reflectie") {
            TextField("Emotie vóór", text: $viewModel.values.emotionBefore)
            TextField("Emotie na", text: $viewModel.values.emotionAfter)
            HStack {
                Text("Rating")
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                StarRatingView(rating: $viewModel.values.rating)
            }
            TextField("Notities", text: $viewModel.values.notes, axis: .vertical)
                .lineLimit(3...8)
        }
    }

    private var screenshotsSection: some View {
        Section("Screenshots") {
            PhotosPicker("Screenshot toevoegen", selection: $photoSelection, maxSelectionCount: 5, matching: .images)
                .onChange(of: photoSelection) { _, newItems in
                    Task {
                        for item in newItems {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                viewModel.addPendingScreenshot(data)
                            }
                        }
                        photoSelection = []
                    }
                }

            if !viewModel.existingScreenshots.isEmpty || !viewModel.pendingScreenshots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.existingScreenshots) { screenshot in
                            screenshotThumbnail(data: screenshot.imageData) {
                                viewModel.removeExistingScreenshot(screenshot, in: modelContext)
                            }
                        }
                        ForEach(Array(viewModel.pendingScreenshots.enumerated()), id: \.offset) { index, data in
                            screenshotThumbnail(data: data) {
                                viewModel.removePendingScreenshot(at: index)
                            }
                        }
                    }
                }
                .listRowBackground(Theme.card)
            }
        }
    }

    private func screenshotThumbnail(data: Data, onRemove: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .padding(4)
        }
    }
}
