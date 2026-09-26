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

    // Screenshot-import (OCR)
    @State private var showingScreenshotSource = false
    @State private var showingOCRPhotoPicker = false
    @State private var ocrPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingScreenshotExample = false

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
                entryStylePicker
                if !viewModel.mode.isEditing {
                    screenshotImportSection
                }
                previewCard
                if !viewModel.missingFields.isEmpty {
                    missingFieldsSection
                } else if viewModel.hasNoPrices {
                    Section {
                        Label("Zonder entry- en exit-prijs wordt de trade opgeslagen, maar telt hij niet mee in P&L en win rate.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                if viewModel.entryStyle == .quick {
                    quickSections
                } else {
                    accountSection
                    instrumentSection
                    timingSection
                    pricesSection
                    costsSection
                    brokerResultSection
                    playbookSection
                    confluencesSection
                    tagsAndMistakesSection
                    reflectionSection
                    screenshotsSection
                }
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
            .confirmationDialog("Screenshot kiezen", isPresented: $showingScreenshotSource, titleVisibility: .visible) {
                Button("Kies uit Foto's") { showingOCRPhotoPicker = true }
                if CameraPickerView.isAvailable {
                    Button("Maak een foto") { showingCamera = true }
                }
                Button("Annuleren", role: .cancel) { }
            } message: {
                Text("De tekst wordt op je toestel gelezen; er gaat niets naar internet.")
            }
            .photosPicker(isPresented: $showingOCRPhotoPicker, selection: $ocrPhotoItem, matching: .images)
            .onChange(of: ocrPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await viewModel.importScreenshot(data, instruments: instruments)
                    } else {
                        viewModel.ocrMessage = "De gekozen afbeelding kon niet geladen worden."
                    }
                    ocrPhotoItem = nil
                }
            }
            .sheet(isPresented: $showingScreenshotExample) {
                ScreenshotExampleSheetView()
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPickerView { data in
                    showingCamera = false
                    guard let data else { return }
                    Task { await viewModel.importScreenshot(data, instruments: instruments) }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Screenshot-import (OCR)

    /// "Vul in vanuit screenshot" plus de status van de laatste import.
    private var screenshotImportSection: some View {
        Section {
            HStack {
                Button {
                    showingScreenshotSource = true
                } label: {
                    Label("Vul in vanuit screenshot", systemImage: "text.viewfinder")
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isRecognizingScreenshot)

                Spacer()

                // Voorbeeld van een geschikte screenshot (zelfde als in de onboarding).
                Button {
                    showingScreenshotExample = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(AppStrings.ScreenshotExample.helpAccessibility)
            }

            if viewModel.isRecognizingScreenshot {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Screenshot wordt gelezen…")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if let message = viewModel.ocrMessage {
                let succeeded = !viewModel.ocrOrigins.isEmpty
                Label(message, systemImage: succeeded ? "sparkles" : "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(succeeded ? Theme.textSecondary : Theme.warning)
            }

            if !viewModel.ocrTradeCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trade op de screenshot")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    FlowLayout(spacing: 8) {
                        ForEach(viewModel.ocrTradeCandidates) { candidate in
                            ChipView(title: candidate.label, color: Theme.accent, selectedForeground: Theme.onAccent, isSelected: candidate.isSelected) {
                                viewModel.selectOCRTrade(candidate.id)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if let pnlText = viewModel.ocrScreenshotPnLText {
                Text(pnlText)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        } footer: {
            if !viewModel.ocrOrigins.isEmpty {
                HStack(spacing: 12) {
                    Label("uit OCR", systemImage: "sparkles")
                    Label("berekend", systemImage: "function")
                }
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    /// Klein icoon achter een veld dat de screenshot-import heeft ingevuld.
    @ViewBuilder
    private func ocrBadge(_ field: ScreenshotField) -> some View {
        if let origin = viewModel.ocrOrigin(for: field) {
            Image(systemName: origin == .recognized ? "sparkles" : "function")
                .font(.caption)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel(origin == .recognized ? "Uit OCR, controleer" : "Berekend uit OCR, controleer")
        }
    }

    /// Chip-rij met alternatieven als de screenshot meerdere kandidaten had.
    @ViewBuilder
    private func ocrAlternatives(_ field: ScreenshotField) -> some View {
        let candidates = viewModel.ocrCandidates(for: field)
        if !candidates.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(candidates) { candidate in
                    ChipView(title: candidate.label, color: Theme.accent, selectedForeground: Theme.onAccent, isSelected: candidate.isSelected) {
                        viewModel.selectOCRCandidate(candidate.id, for: field)
                    }
                }
            }
            .padding(.vertical, 2)
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

    // MARK: - Uitgebreid / snel

    private var entryStylePicker: some View {
        Picker("Invoer", selection: $viewModel.entryStyle) {
            ForEach(TradeFormViewModel.EntryStyle.allCases) { style in
                Text(style.displayName).tag(style)
            }
        }
        .pickerStyle(.segmented)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    /// Snelle invoer: account, symbool, richting/datum, winst of verlies en
    /// confluences (plus optioneel een notitie).
    @ViewBuilder
    private var quickSections: some View {
        accountSection

        Section("Instrument") {
            Picker("Preset", selection: presetBinding) {
                Text("Handmatig").tag(Optional<Instrument>.none)
                ForEach(instruments) { instrument in
                    Text("\(instrument.symbol) — \(instrument.name)").tag(Optional(instrument))
                }
            }
            symbolField
        }

        Section("Resultaat") {
            Picker("Resultaat", selection: $viewModel.quickIsProfit) {
                Text("Winst").tag(true)
                Text("Verlies").tag(false)
            }
            .pickerStyle(.segmented)
            numberRow("Bedrag ($)", value: $viewModel.quickAmount, ocrField: .netPnL)
            directionPicker
            entryDatePicker("Datum")
        }

        confluencesSection

        Section("Notitie") {
            TextField("Optioneel", text: $viewModel.values.notes, axis: .vertical)
                .lineLimit(2...6)
        }
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
            symbolField
            numberRow("Tick size", value: $viewModel.values.tickSize)
            numberRow("Tick value ($)", value: $viewModel.values.tickValue)
        }
    }

    private var symbolField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Symbool", text: $viewModel.values.symbol)
                    .textInputAutocapitalization(.characters)
                ocrBadge(.symbol)
            }
            ocrAlternatives(.symbol)
        }
    }

    private var directionPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Richting", selection: $viewModel.values.direction) {
                    ForEach(TradeDirection.allCases) { direction in
                        Text(direction.displayName).tag(direction)
                    }
                }
                .pickerStyle(.segmented)
                ocrBadge(.direction)
            }
            ocrAlternatives(.direction)
        }
    }

    private func entryDatePicker(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            DatePicker(selection: $viewModel.values.entryDate) {
                HStack(spacing: 6) {
                    Text(title)
                    ocrBadge(.entryTime)
                }
            }
            ocrAlternatives(.entryTime)
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
            directionPicker

            entryDatePicker("Entry")

            Toggle("Trade is gesloten", isOn: closedBinding)

            if viewModel.values.exitDate != nil {
                VStack(alignment: .leading, spacing: 6) {
                    DatePicker(selection: exitDateBinding) {
                        HStack(spacing: 6) {
                            Text("Exit")
                            ocrBadge(.exitTime)
                        }
                    }
                    ocrAlternatives(.exitTime)
                }
            }
        }
    }

    private var closedBinding: Binding<Bool> {
        Binding<Bool>(
            get: { viewModel.values.exitDate != nil },
            set: { isClosed in
                if isClosed {
                    viewModel.values.exitDate = max(viewModel.values.entryDate, Date())
                    if viewModel.values.exitPrice == nil, viewModel.values.entryPrice != 0 {
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
            numberRow("Entry-prijs", value: $viewModel.values.entryPrice, ocrField: .entryPrice)
            if viewModel.values.exitDate != nil {
                numberRow("Exit-prijs", value: exitPriceBinding, ocrField: .exitPrice)
            }
            numberRow("Aantal contracten/lots", value: $viewModel.values.quantity, ocrField: .quantity)
            numberRow("Stop loss", value: optionalDoubleBinding(\.stopLoss), ocrField: .stopLoss)
            numberRow("Take profit", value: optionalDoubleBinding(\.takeProfit), ocrField: .takeProfit)
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
            numberRow("Commissie", value: $viewModel.values.commission, ocrField: .commission)
            numberRow("Fees", value: $viewModel.values.fees, ocrField: .fees)
        }
    }

    /// Resultaat zoals de broker het toont; gaat vóór de berekening uit prijzen.
    private var brokerResultSection: some View {
        Section {
            numberRow("Netto P&L", value: brokerNetPnLBinding, ocrField: .netPnL)
        } header: {
            Text("Resultaat volgens broker")
        } footer: {
            Text("Leeg: P&L uit prijzen, aantal en tick value. Ingevuld (bijv. van de screenshot, in de valuta van je account) gaat dit bedrag voor.")
        }
    }

    private var brokerNetPnLBinding: Binding<Double> {
        Binding<Double>(
            get: { viewModel.brokerNetPnL ?? 0 },
            set: { viewModel.brokerNetPnL = $0 == 0 ? nil : $0 }
        )
    }

    /// Getalrij; met `ocrField` ook het "uit OCR"-icoon en eventuele alternatieven.
    private func numberRow(_ title: String, value: Binding<Double>, ocrField: ScreenshotField? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .foregroundStyle(Theme.textPrimary)
                if let ocrField {
                    ocrBadge(ocrField)
                }
                Spacer()
                DecimalFieldView(title: title, value: value)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.textPrimary)
            }
            if let ocrField {
                ocrAlternatives(ocrField)
            }
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
