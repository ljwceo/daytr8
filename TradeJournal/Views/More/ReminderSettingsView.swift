import SwiftUI

/// Instellingen voor de lokale "vul je journal in"-herinnering.
struct ReminderSettingsView: View {

    @State private var viewModel = ReminderSettingsViewModel()

    var body: some View {
        Form {
            Section {
                Toggle("Journal-herinnering", isOn: $viewModel.isEnabled)
                if viewModel.isEnabled {
                    DatePicker("Tijdstip", selection: $viewModel.time, displayedComponents: .hourAndMinute)
                    Toggle("Alleen op werkdagen", isOn: $viewModel.weekdaysOnly)
                }
            } footer: {
                Text("Een lokale melding op dit toestel — er gaat niets via internet.")
            }
            .listRowBackground(Theme.card)

            if viewModel.isEnabled {
                Section("Tekst") {
                    TextField("Melding", text: $viewModel.message, axis: .vertical)
                        .lineLimit(1...4)
                }
                .listRowBackground(Theme.card)
            }

            if viewModel.permissionDenied {
                Section {
                    Text("Meldingen staan uit voor TradeJournal. Zet ze aan via Instellingen > Meldingen > TradeJournal.")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
                .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Herinneringen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onChange(of: viewModel.isEnabled) { _, _ in apply() }
        .onChange(of: viewModel.time) { _, _ in apply() }
        .onChange(of: viewModel.weekdaysOnly) { _, _ in apply() }
        .onSubmit { apply() }
        .onDisappear { apply() }
    }

    private func apply() {
        Task { await viewModel.apply() }
    }
}
