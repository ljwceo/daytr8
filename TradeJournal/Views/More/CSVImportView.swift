import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// CSV-import (SPEC §9): bestand kiezen → preset of eigen kolommapping →
/// voorbeeld met duplicaatdetectie → importeren.
///
/// Wordt als sheet getoond vanuit de Meer-tab.
struct CSVImportView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \Instrument.sortOrder) private var instruments: [Instrument]
    @Query private var existingTrades: [Trade]

    @State private var viewModel = CSVImportViewModel()
    @State private var isImporterPresented = false
    @State private var showPreview = false

    /// Tijdzones die in broker-exports het vaakst voorkomen.
    private let timeZoneOptions: [String] = {
        var zones = [TimeZone.current.identifier, "America/New_York", "America/Chicago", "UTC", "Europe/London", "Europe/Amsterdam"]
        var seen = Set<String>()
        zones = zones.filter { seen.insert($0).inserted }
        return zones
    }()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.table == nil {
                    introView
                } else {
                    mappingForm
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("CSV importeren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluiten") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]
            ) { result in
                switch result {
                case .success(let url):
                    viewModel.loadFile(at: url)
                    if viewModel.account == nil {
                        viewModel.account = accounts.first
                    }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
            .navigationDestination(isPresented: $showPreview) {
                CSVImportPreviewView(viewModel: viewModel, instruments: instruments) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Intro

    private var introView: some View {
        List {
            Section {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Kies CSV-bestand…", systemImage: "doc.badge.plus")
                }
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.loss)
                }
            } footer: {
                Text("Exporteer je trades of fills uit je platform als CSV en kies het bestand hier. Losse fills worden automatisch samengevoegd tot trades; trades die al in je journal staan worden als duplicaat herkend.")
            }

            Section("Ondersteunde presets") {
                ForEach(CSVImportPresets.all) { preset in
                    HStack {
                        Text(preset.name)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(preset.mode.displayName)
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Mapping

    private var mappingForm: some View {
        Form {
            Section("Bestand") {
                HStack {
                    Label(viewModel.fileName, systemImage: "doc.text")
                        .lineLimit(1)
                    Spacer()
                    Text("\(viewModel.table?.rows.count ?? 0) rijen")
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
                Button("Ander bestand kiezen…") { isImporterPresented = true }
            }

            Section {
                Picker("Preset", selection: Binding(
                    get: { viewModel.selectedPresetID },
                    set: { viewModel.applyPreset(id: $0) }
                )) {
                    Text("Eigen mapping").tag(Optional<String>.none)
                    ForEach(CSVImportPresets.all) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }

                Picker("Rijen zijn", selection: Binding(
                    get: { viewModel.mapping.mode },
                    set: { viewModel.setMode($0) }
                )) {
                    ForEach(CSVImportMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Datumnotatie", selection: $viewModel.mapping.dateOrder) {
                    ForEach(ImportDateOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }

                Picker("Tijdzone van export", selection: $viewModel.mapping.timeZoneIdentifier) {
                    ForEach(timeZoneOptions, id: \.self) { identifier in
                        Text(identifier).tag(identifier)
                    }
                }
            } header: {
                Text("Formaat")
            } footer: {
                Text("De tijdzone wordt alleen gebruikt voor tijden zonder expliciete offset.")
            }

            Section("Account") {
                Picker("Importeer naar", selection: $viewModel.account) {
                    Text("Geen account").tag(Optional<Account>.none)
                    ForEach(accounts) { account in
                        Text(account.name).tag(Optional(account))
                    }
                }
            }

            Section {
                ForEach(CSVImportField.fields(for: viewModel.mapping.mode)) { field in
                    columnPicker(for: field)
                }
            } header: {
                Text("Kolommen koppelen")
            } footer: {
                Text(viewModel.mapping.mode == .fills
                     ? "Elke rij is een fill. Zonder koop/verkoop-kolom bepaalt het teken van het aantal de kant."
                     : "Koppel entry/exit, of — voor exports met koop- en verkooptijd (zoals Tradovate) — de koop/verkoop-kolommen.")
            }

            Section {
                ForEach(viewModel.validationErrors, id: \.self) { error in
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
                Button {
                    viewModel.buildPreview(existingTrades: existingTrades, instruments: instruments)
                    showPreview = true
                } label: {
                    Label("Voorbeeld bekijken", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!viewModel.canBuildPreview)
            }
        }
    }

    private func columnPicker(for field: CSVImportField) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Picker(field.displayName, selection: Binding(
                get: { viewModel.column(for: field) },
                set: { viewModel.setColumn($0, for: field) }
            )) {
                Text("—").tag(Optional<Int>.none)
                ForEach(Array(viewModel.headers.enumerated()), id: \.offset) { index, header in
                    Text(header.isEmpty ? "Kolom \(index + 1)" : header).tag(Optional(index))
                }
            }
            if let sample = viewModel.sampleValue(for: field) {
                Text("bijv. \(sample)")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Voorbeeld

/// Voorbeeldlijst met nieuwe trades, duplicaten en probleemrijen.
private struct CSVImportPreviewView: View {

    @Environment(\.modelContext) private var modelContext

    @Bindable var viewModel: CSVImportViewModel
    let instruments: [Instrument]
    let onFinished: () -> Void

    var body: some View {
        List {
            if let imported = viewModel.importedCount {
                Section {
                    Label("\(imported) trades geïmporteerd.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.profit)
                    Button("Klaar", action: onFinished)
                }
            } else {
                summarySection
            }

            if !viewModel.unknownInstrumentSymbols.isEmpty {
                Section {
                    Label("Geen instrument-preset voor: \(viewModel.unknownInstrumentSymbols.joined(separator: ", ")). De P&L wordt afgeleid uit de P&L-kolom (indien gekoppeld) of met puntwaarde 1 berekend.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
            }

            Section("Trades (\(viewModel.previewItems.count))") {
                if viewModel.previewItems.isEmpty {
                    Text("Geen trades gevonden. Controleer de kolomkoppeling.")
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(viewModel.previewItems) { item in
                    CSVImportPreviewRow(item: item)
                }
            }

            if let issues = viewModel.extraction?.issues, !issues.isEmpty {
                Section("Overgeslagen rijen (\(issues.count))") {
                    ForEach(issues) { issue in
                        HStack(alignment: .top) {
                            Text("Rij \(issue.row)")
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                            Text(issue.message)
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .font(.footnote)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Voorbeeld")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summarySection: some View {
        Section {
            HStack {
                summaryTile(title: "Nieuw", value: viewModel.newCount, color: Theme.profit)
                summaryTile(title: "Duplicaat", value: viewModel.duplicateCount, color: Theme.warning)
                summaryTile(title: "Fout", value: viewModel.extraction?.issues.count ?? 0, color: Theme.loss)
            }
            if viewModel.duplicateCount > 0 {
                Toggle("Duplicaten toch importeren", isOn: $viewModel.includeDuplicates)
            }
            Button {
                viewModel.importTrades(instruments: instruments, in: modelContext)
            } label: {
                Label("Importeer \(viewModel.tradesToImportCount) trades", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .disabled(viewModel.tradesToImportCount == 0)
        }
    }

    private func summaryTile(title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Eén regel in het voorbeeld.
private struct CSVImportPreviewRow: View {

    let item: CSVImportService.PreviewItem

    private var trade: ImportedTrade { item.trade }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: trade.direction == .long ? "arrow.up.right" : "arrow.down.right")
                .foregroundStyle(trade.direction == .long ? Theme.profit : Theme.loss)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(trade.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(trade.direction.displayName) × \(formatted(trade.quantity))")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if item.isDuplicate {
                        Text("Duplicaat")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: Theme.smallCornerRadius).fill(Theme.warning.opacity(0.2)))
                            .foregroundStyle(Theme.warning)
                    }
                    if trade.isOpen {
                        Text("Open")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.neutral)
                    }
                }
                Text(trade.entryDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(formatted(trade.entryPrice)) → \(trade.exitPrice.map { formatted($0) } ?? "—")")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                if let pnl = trade.reportedPnL {
                    Text(pnl.formatted(.currency(code: "USD")))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.color(forPnL: pnl))
                        .monospacedDigit()
                } else if !trade.fills.isEmpty {
                    Text("\(trade.fills.count) fills")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .opacity(item.isDuplicate ? 0.6 : 1)
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...5)))
    }
}
