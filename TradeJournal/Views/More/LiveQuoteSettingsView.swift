import SwiftUI

/// Instellingen voor de live-koerskaart op het dashboard.
struct LiveQuoteSettingsView: View {

    @AppStorage(LiveQuoteSettings.Keys.isEnabled) private var isEnabled = true
    @AppStorage(LiveQuoteSettings.Keys.symbolOverride) private var symbolOverride = ""

    var body: some View {
        Form {
            Section {
                Toggle("Live koers op dashboard", isOn: $isEnabled)
            } footer: {
                Text("Haalt koersen op via Yahoo Finance (gratis, geen account). Dit is de enige functie die internet gebruikt; er wordt niets van je journal verstuurd, alleen het symbool.")
            }
            .listRowBackground(Theme.card)

            if isEnabled {
                Section {
                    TextField("Automatisch (laatst getrade instrument)", text: $symbolOverride)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if let resolved = QuoteSymbolResolver.resolve(symbolOverride), !symbolOverride.trimmingCharacters(in: .whitespaces).isEmpty {
                        LabeledContent("Koersbron-symbool", value: resolved.providerSymbol)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } header: {
                    Text("Vast symbool")
                } footer: {
                    Text("Leeg laten om het instrument van je laatste trade te volgen. Futures (bijv. MNQZ26) worden aan het doorlopende contract gekoppeld (MNQ=F).")
                }
                .listRowBackground(Theme.card)

                Section("Vertraging") {
                    Text("CME-futures zijn ongeveer 10 minuten vertraagd, aandelen en indexen meestal realtime tot 15 minuten. De kaart toont altijd of de koers vertraagd is.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Live koers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
