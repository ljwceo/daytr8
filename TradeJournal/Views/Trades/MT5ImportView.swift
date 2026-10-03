import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Bulk-import van trades vanaf screenshots van de MetaTrader 5-geschiedenis
/// (iOS-app, History-tab). Kiezen (meerdere screenshots) → OCR op het
/// toestel → verplicht controlescherm → importeren → samenvatting.
///
/// Alleen de harde cijfers (symbool, richting, volume, entry, exit,
/// sluittijd, P&L); geïmporteerde trades krijgen de markering "snel
/// toegevoegd" en de screenshot als bijlage.
struct MT5ImportView: View {

    /// Na afloop: naar het trade log met de filter "Snel toegevoegd".
    var onShowQuickAdded: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Trade.entryDate, order: .reverse) private var trades: [Trade]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \Playbook.name) private var playbooks: [Playbook]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query private var instruments: [Instrument]

    @State private var viewModel = MT5ImportViewModel()
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var editingRowID: UUID?
    @State private var confirmImport = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                switch viewModel.phase {
                case .picking:
                    pickingView
                case .recognizing(let current, let total):
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Screenshot \(current) van \(total) lezen…")
                            .foregroundStyle(Theme.textSecondary)
                        Text("De tekst wordt op je toestel gelezen; er gaat niets naar internet.")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(Theme.cardPadding)
                case .review:
                    reviewList
                case .finished(let summary):
                    summaryView(summary)
                }
            }
            .navigationTitle("MT5-import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { toolbarContent }
            .navigationDestination(item: $editingRowID) { id in
                MT5ImportRowEditorView(viewModel: viewModel, rowID: id)
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await load(items) }
            }
            .confirmationDialog(importQuestion, isPresented: $confirmImport, titleVisibility: .visible) {
                Button("Importeren") {
                    viewModel.importSelected(accounts: accounts, playbooks: playbooks, tags: tags, instruments: instruments, in: modelContext)
                }
                Button("Annuleren", role: .cancel) { }
            } message: {
                Text(importMessage)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if case .finished = viewModel.phase {
                EmptyView()
            } else {
                Button("Annuleren") { dismiss() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            switch viewModel.phase {
            case .review:
                Button("Importeren (\(viewModel.selectedCount))") { confirmImport = true }
                    .disabled(!viewModel.canImport)
            case .finished:
                Button("Klaar") { dismiss() }
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Kiezen

    private var pickingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Screenshots van de MT5-geschiedenis", systemImage: "text.viewfinder")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Open in de MetaTrader 5-app de History-tab en maak screenshots terwijl je doorscrollt. Kies ze hier allemaal tegelijk (max. \(MT5ImportViewModel.maxScreenshots)); dubbele trades worden samengevoegd.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Alleen symbool, richting, volume, entry, exit, sluittijd en P&L worden gelezen. Confluences, playbook en notities vul je later per trade aan (filter \"Snel toegevoegd\" in het trade log).")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(Theme.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

                if let message = viewModel.message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.warning)
                }

                PhotosPicker(selection: $photoItems, maxSelectionCount: MT5ImportViewModel.maxScreenshots, selectionBehavior: .ordered, matching: .images) {
                    Label("Kies screenshots", systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(Theme.onAccent)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                }
            }
            .padding(Theme.cardPadding)
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        var images: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) { images.append(data) }
        }
        photoItems = []
        guard !images.isEmpty else {
            viewModel.message = "De gekozen afbeeldingen konden niet geladen worden."
            return
        }
        let defaultAccount = accounts.first { !$0.isArchived && $0.type != .backtest } ?? accounts.first
        await viewModel.recognize(images, existingTrades: trades, instruments: instruments, defaultAccountID: defaultAccount?.id)
    }

    // MARK: - Controleren

    private var reviewList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(viewModel.rows.count) trades herkend op \(viewModel.screenshots.count) screenshot\(viewModel.screenshots.count == 1 ? "" : "s")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if viewModel.mergedCount > 0 {
                        Text("\(viewModel.mergedCount) dubbel op de screenshots, samengevoegd")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    if viewModel.duplicateCount > 0 {
                        Text("\(viewModel.duplicateCount) staan al in je journal (niet aangevinkt)")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    if viewModel.rowsWithIssues > 0 {
                        Text("\(viewModel.rowsWithIssues) met een melding: controleer de gemarkeerde velden. Trades met een rode melding kunnen pas mee na correctie.")
                            .font(.caption).foregroundStyle(Theme.warning)
                    }
                    if let message = viewModel.message {
                        Text(message).font(.caption).foregroundStyle(Theme.warning)
                    }
                }
            }
            .listRowBackground(Theme.card)

            Section {
                Picker("Account", selection: $viewModel.bulkAccountID) {
                    Text("Geen account").tag(UUID?.none)
                    ForEach(accounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                Picker("Playbook (optioneel)", selection: $viewModel.bulkPlaybookID) {
                    Text("Geen").tag(UUID?.none)
                    ForEach(playbooks.filter { !$0.isArchived }) { playbook in
                        Text(playbook.name).tag(Optional(playbook.id))
                    }
                }
                Picker("Tag (optioneel)", selection: $viewModel.bulkTagID) {
                    Text("Geen").tag(UUID?.none)
                    ForEach(tags) { tag in
                        Text(tag.name).tag(Optional(tag.id))
                    }
                }
            } header: {
                Text("Voor alle geselecteerde trades")
            } footer: {
                Text("Geldt bij het importeren voor alle aangevinkte trades.")
            }
            .listRowBackground(Theme.card)

            Section {
                ForEach(viewModel.rows) { row in
                    MT5ImportRowView(row: row, onToggle: { viewModel.toggle(row.id) }, onOpen: { editingRowID = row.id })
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.delete(row.id)
                            } label: {
                                Label("Verwijderen", systemImage: "trash")
                            }
                        }
                }
            } header: {
                HStack {
                    Text("Trades")
                    Spacer()
                    Button("Alles") { viewModel.setAllSelected(true) }
                    Text("·")
                    Button("Niets") { viewModel.setAllSelected(false) }
                }
                .font(.caption)
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    private var importQuestion: String {
        "\(viewModel.selectedCount) trade\(viewModel.selectedCount == 1 ? "" : "s") importeren?"
    }

    private var importMessage: String {
        let account = accounts.first { $0.id == viewModel.bulkAccountID }?.name ?? "geen account"
        return "Ze worden opgeslagen onder \(account), met de screenshot als bijlage en de markering \"snel toegevoegd\"."
    }

    // MARK: - Samenvatting

    private func summaryView(_ summary: MT5ImportSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("\(summary.imported) trade\(summary.imported == 1 ? "" : "s") geïmporteerd", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.profit)

                VStack(alignment: .leading, spacing: 10) {
                    summaryRow("Geïmporteerd", summary.imported)
                    summaryRow("Overgeslagen als duplicaat", summary.skippedAsDuplicate)
                    if summary.skippedAsDuplicate > 0 {
                        Text("\(summary.skippedExisting) stond al in je journal, \(summary.mergedOnScreenshots) dubbel op de screenshots.")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    summaryRow("Handmatig gecorrigeerd", summary.corrected)
                    if summary.notSelected > 0 {
                        summaryRow("Niet aangevinkt (niet opgeslagen)", summary.notSelected)
                    }
                }
                .padding(Theme.cardPadding)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

                Text("Vul confluences, playbook en notities later aan via het trade log (filter \"Snel toegevoegd\").")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                if let onShowQuickAdded, summary.imported > 0 {
                    Button {
                        onShowQuickAdded()
                        dismiss()
                    } label: {
                        Label("Toon snel toegevoegde trades", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .foregroundStyle(Theme.accent)
                }

                Button("Nog meer screenshots importeren") { viewModel.reset() }
                    .foregroundStyle(Theme.accent)
            }
            .padding(Theme.cardPadding)
        }
    }

    private func summaryRow(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(value)").font(.headline.monospacedDigit()).foregroundStyle(Theme.textPrimary)
        }
    }
}

// MARK: - Regel in het controlescherm

/// Eén herkende trade, opgemaakt zoals in MT5 (twee regels), met gemarkeerde
/// velden en de meldingen eronder.
struct MT5ImportRowView: View {

    let row: MT5ImportRow
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: row.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(row.hasErrors ? Theme.textTertiary : (row.isSelected ? Theme.accent : Theme.textSecondary))
            }
            .buttonStyle(.plain)
            .disabled(row.hasErrors)
            .accessibilityLabel(row.isSelected ? "Niet importeren" : "Importeren")

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        field(row.hasValue(.symbol) ? row.symbol : "Symbool?", .symbol, weight: .semibold)
                        field(row.direction.map { $0 == .long ? "buy" : "sell" } ?? "richting?", .direction)
                        field(row.volume.map(MT5ImportFormat.number) ?? "volume?", .volume)
                        Spacer(minLength: 4)
                        field(row.pnl.map(MT5ImportFormat.amount) ?? "P&L?", .pnl, weight: .semibold, color: row.pnl.map { Theme.color(forPnL: $0) })
                    }
                    HStack(spacing: 6) {
                        field(row.entryPrice.map(MT5ImportFormat.number) ?? "entry?", .entryPrice)
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(Theme.textTertiary)
                        field(row.exitPrice.map(MT5ImportFormat.number) ?? "exit?", .exitPrice)
                        Spacer(minLength: 4)
                        field(row.closeTime.map(MT5ImportFormat.dateTime) ?? "sluittijd?", .closeTime)
                    }
                    ForEach(Array(row.issues.enumerated()), id: \.offset) { _, issue in
                        Label(issue.message, systemImage: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(issue.severity == .error ? Theme.loss : Theme.warning)
                    }
                    if row.isEdited {
                        Label("Gecorrigeerd", systemImage: "pencil")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .opacity(row.isSelected || row.hasErrors ? 1 : 0.7)
    }

    private func field(_ text: String, _ field: MT5ParsedTrade.Field, weight: Font.Weight = .regular, color: Color? = nil) -> some View {
        let issues = row.issues(for: field)
        let highlight: Color? = issues.contains { $0.severity == .error } ? Theme.loss : (issues.isEmpty ? nil : Theme.warning)
        return Text(text)
            .font(.subheadline.weight(weight).monospacedDigit())
            .foregroundStyle(highlight ?? color ?? Theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, highlight == nil ? 0 : 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill((highlight ?? .clear).opacity(0.15))
            )
    }
}

/// Opmaak van getallen in het controlescherm.
enum MT5ImportFormat {
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...6)).grouping(.never))
    }

    static func amount(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
    }
}

// MARK: - Regel bewerken

/// Alle velden van één herkende trade, per veld te corrigeren. Onzekere
/// velden zijn gemarkeerd; "Bewaar" neemt de wijzigingen over en keurt de
/// rest goed.
struct MT5ImportRowEditorView: View {

    let viewModel: MT5ImportViewModel
    let rowID: UUID

    @Environment(\.dismiss) private var dismiss

    @State private var symbol = ""
    @State private var direction: TradeDirection?
    @State private var volume = ""
    @State private var entry = ""
    @State private var exit = ""
    @State private var pnl = ""
    @State private var closeTime = Date()
    @State private var hasCloseTime = false
    @State private var didLoad = false

    private var row: MT5ImportRow? { viewModel.rows.first { $0.id == rowID } }

    var body: some View {
        Form {
            if let row {
                if !row.sourceLines.isEmpty {
                    Section("Herkende tekst") {
                        ForEach(Array(row.sourceLines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption.monospaced()).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .listRowBackground(Theme.card)
                }

                Section("Trade") {
                    labeled(.symbol, row: row) {
                        TextField("bijv. AUDCAD", text: $symbol)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    labeled(.direction, row: row) {
                        Picker("Richting", selection: $direction) {
                            Text("Buy").tag(TradeDirection?.some(.long))
                            Text("Sell").tag(TradeDirection?.some(.short))
                        }
                        .pickerStyle(.segmented)
                    }
                    labeled(.volume, row: row) { numberField("lots", text: $volume, keyboard: .decimalPad) }
                    labeled(.entryPrice, row: row) { numberField("prijs", text: $entry, keyboard: .decimalPad) }
                    labeled(.exitPrice, row: row) { numberField("prijs", text: $exit, keyboard: .decimalPad) }
                    labeled(.pnl, row: row) { numberField("bijv. -1 270.65", text: $pnl, keyboard: .numbersAndPunctuation) }
                    labeled(.closeTime, row: row) {
                        if hasCloseTime {
                            DatePicker("", selection: $closeTime, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                        } else {
                            Button("Instellen") {
                                hasCloseTime = true
                            }
                        }
                    }
                }
                .listRowBackground(Theme.card)

                if !row.issues.isEmpty {
                    Section("Meldingen") {
                        ForEach(Array(row.issues.enumerated()), id: \.offset) { _, issue in
                            Label(issue.message, systemImage: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .foregroundStyle(issue.severity == .error ? Theme.loss : Theme.warning)
                        }
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    Button("Verwijderen uit deze import", role: .destructive) {
                        viewModel.delete(rowID)
                        dismiss()
                    }
                }
                .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Trade controleren")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Bewaar") {
                    save()
                    dismiss()
                }
            }
        }
        .onAppear(perform: load)
    }

    private func labeled<Content: View>(_ field: MT5ParsedTrade.Field, row: MT5ImportRow, @ViewBuilder content: () -> Content) -> some View {
        let issues = row.issues(for: field)
        let color: Color = issues.contains { $0.severity == .error } ? Theme.loss : (issues.isEmpty ? Theme.textPrimary : Theme.warning)
        return HStack {
            Text(field.displayName).foregroundStyle(color)
            if !issues.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(color)
            }
            Spacer(minLength: 8)
            content()
        }
    }

    private func numberField(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
    }

    private func load() {
        guard !didLoad, let row else { return }
        didLoad = true
        symbol = row.symbol
        direction = row.direction
        volume = row.volume.map(MT5ImportFormat.number) ?? ""
        entry = row.entryPrice.map(MT5ImportFormat.number) ?? ""
        exit = row.exitPrice.map(MT5ImportFormat.number) ?? ""
        pnl = row.pnl.map { String(format: "%.2f", $0) } ?? ""
        if let time = row.closeTime {
            closeTime = time
            hasCloseTime = true
        }
    }

    private func save() {
        guard let row else { return }
        let newVolume = DecimalInput.parse(volume)
        let newEntry = DecimalInput.parse(entry)
        let newExit = DecimalInput.parse(exit)
        let newPnL = MT5HistoryParser.parseAmount(pnl)?.value ?? DecimalInput.parse(pnl)
        // Seconden van de gelezen tijd behouden als de minuut niet veranderd is.
        var newCloseTime: Date? = hasCloseTime ? closeTime : nil
        if let original = row.closeTime, let picked = newCloseTime,
           Calendar.current.isDate(original, equalTo: picked, toGranularity: .minute) {
            newCloseTime = original
        }

        viewModel.update(rowID) { edited in
            edited.symbol = symbol.trimmingCharacters(in: .whitespaces).uppercased()
            edited.direction = direction
            edited.volume = newVolume
            edited.entryPrice = newEntry
            edited.exitPrice = newExit
            edited.pnl = newPnL
            edited.closeTime = newCloseTime
        }
        // Wat niet gewijzigd is maar wel bekeken: goedgekeurd.
        for field in row.uncertainFields {
            viewModel.confirm(field, of: rowID)
        }
    }
}
