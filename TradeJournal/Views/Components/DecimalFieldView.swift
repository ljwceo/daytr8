import SwiftUI

/// Getalveld dat de binding bij elke toetsaanslag bijwerkt.
///
/// `TextField(value:format:)` geeft een waarde pas door als het veld de focus
/// verliest; met het decimalPad (geen Enter-toets) bleef "Opslaan" daardoor
/// uitgeschakeld als je na het typen van bijv. de entry-prijs meteen op
/// opslaan tikte. Leeg veld = 0.
struct DecimalFieldView: View {

    let title: String
    @Binding var value: Double

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(.decimalPad)
            .focused($isFocused)
            .onAppear { text = DecimalInput.format(value) }
            .onChange(of: text) { _, newText in
                if let parsed = DecimalInput.parse(newText) {
                    if parsed != value { value = parsed }
                } else if newText.trimmingCharacters(in: .whitespaces).isEmpty, value != 0 {
                    value = 0
                }
            }
            .onChange(of: value) { _, newValue in
                // Van buitenaf gewijzigd (bijv. preset gekozen): tekst bijwerken,
                // maar niet terwijl de gebruiker zelf aan het typen is.
                if !isFocused, DecimalInput.parse(text) != newValue {
                    text = DecimalInput.format(newValue)
                }
            }
            .onChange(of: isFocused) { _, focused in
                // Na het typen netjes formatteren ("18000," → "18000").
                if !focused { text = DecimalInput.format(value) }
            }
    }
}
