import SwiftUI
import SwiftData

/// Formulier voor een account met doelen en limieten.
struct AccountFormView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: AccountFormViewModel

    init(mode: AccountFormViewModel.Mode) {
        _viewModel = State(initialValue: AccountFormViewModel(mode: mode))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Naam (bijv. Topstep 50k #3)", text: $viewModel.draft.name)
                    Picker("Type", selection: $viewModel.draft.type) {
                        ForEach(AccountType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    TextField("Broker / prop firm", text: $viewModel.draft.broker)
                    Picker("Valuta", selection: $viewModel.draft.currency) {
                        ForEach(currencyOptions, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    numberRow("Startbalans", value: $viewModel.draft.startingBalance)
                }
                .listRowBackground(Theme.card)

                Section {
                    numberRow("Maandelijks P&L-doel", value: optionalBinding(\.monthlyProfitTarget))
                    numberRow("Daily loss limit", value: optionalBinding(\.dailyLossLimit))
                    numberRow("Max drawdown (trailing)", value: optionalBinding(\.maxDrawdown))
                } header: {
                    Text("Doelen & limieten")
                } footer: {
                    Text("Laat op 0 om niet in te stellen. Het dashboard waarschuwt vanaf \(Int(GoalsService.defaultWarningFraction * 100))% van een limiet.")
                }
                .listRowBackground(Theme.card)

                if viewModel.draft.type == .backtest {
                    Section {
                        Text("Trades in dit account tellen niet mee in je live statistieken.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.card)
                }

                if viewModel.isEditing {
                    Section {
                        Toggle("Gearchiveerd", isOn: $viewModel.draft.isArchived)
                    }
                    .listRowBackground(Theme.card)
                }

                if !viewModel.validationErrors.isEmpty {
                    Section {
                        ForEach(viewModel.validationErrors, id: \.self) { error in
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(Theme.warning)
                        }
                    }
                    .listRowBackground(Theme.card)
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
        }
    }

    /// Standaardvaluta's plus de huidige valuta als die afwijkt.
    private var currencyOptions: [String] {
        let base = AccountFormViewModel.currencies
        return base.contains(viewModel.draft.currency) ? base : base + [viewModel.draft.currency]
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

    /// 0 in het veld = niet ingesteld (`nil`).
    private func optionalBinding(_ keyPath: WritableKeyPath<AccountFormViewModel.Draft, Double?>) -> Binding<Double> {
        Binding(
            get: { viewModel.draft[keyPath: keyPath] ?? 0 },
            set: { viewModel.draft[keyPath: keyPath] = $0 > 0 ? $0 : nil }
        )
    }
}
