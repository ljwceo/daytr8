import SwiftUI

/// Instellingen voor het optionele app-slot (Face ID / Touch ID / code).
struct AppLockSettingsView: View {

    let viewModel: AppLockViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Vergrendel met \(viewModel.methodName)", isOn: enabledBinding)
                if viewModel.isEnabled {
                    Picker("Opnieuw vergrendelen", selection: gracePeriodBinding) {
                        ForEach(AppLockService.gracePeriodOptions, id: \.self) { option in
                            Text(label(for: option)).tag(option)
                        }
                    }
                }
            } footer: {
                Text("Bij het openen van de app vraagt TradeJournal om \(viewModel.methodName). Lukt dat niet, dan kun je je toegangscode gebruiken.")
            }
            .listRowBackground(Theme.card)

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
                .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("App-slot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isEnabled },
            set: { newValue in Task { await viewModel.setEnabled(newValue) } }
        )
    }

    private var gracePeriodBinding: Binding<TimeInterval> {
        Binding(
            get: { viewModel.gracePeriod },
            set: { viewModel.setGracePeriod($0) }
        )
    }

    private func label(for seconds: TimeInterval) -> String {
        switch seconds {
        case 0: return "Direct"
        case 60: return "Na 1 minuut"
        default: return "Na \(Int(seconds / 60)) minuten"
        }
    }
}
