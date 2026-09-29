import Foundation
import Observation

/// Thema-editor (Meer → Thema → Nieuw thema / bewerken): één concept-thema
/// met live palet, kleurkeuze per veld via HSB (kleurenwiel) of HEX,
/// contrastcontrole, genereren vanuit het accent en opslaan in `ThemeStore`.
@Observable
final class ThemeEditorViewModel {

    var draft: CustomTheme
    let isNew: Bool

    /// Veld waarvan de kleur nu in het wiel staat.
    private(set) var selectedField: CustomTheme.Field = .accent

    /// HSB van het gekozen veld. Apart bewaard zodat de tint niet wegvalt
    /// bij verzadiging of helderheid 0.
    private(set) var selectedHSB: HSBColor

    /// Tekst in het HEX-veld.
    var hexInput: String

    init(theme: CustomTheme?, basedOn palette: ThemePalette) {
        let draft = theme ?? CustomTheme(name: AppStrings.Themes.defaultCustomName, basedOn: palette)
        self.draft = draft
        self.isNew = theme == nil
        self.selectedHSB = HSBColor(draft[.accent])
        self.hexInput = draft[.accent].hex
    }

    // MARK: - Afgeleid

    /// Het volledige palet zoals de app het zou tonen (live preview).
    var palette: ThemePalette { draft.palette }

    var contrastIssues: [ThemePaletteGenerator.ContrastIssue] {
        ThemePaletteGenerator.contrastIssues(for: draft)
    }

    var isHexInputValid: Bool { HexColor.isValidHex(hexInput) }

    var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Kleur kiezen

    func select(_ field: CustomTheme.Field) {
        selectedField = field
        syncSelection()
    }

    /// Nieuwe kleur uit het wiel of de sliders.
    func updateSelectedColor(_ hsb: HSBColor) {
        selectedHSB = hsb
        draft[selectedField] = hsb.hexColor
        hexInput = draft[selectedField].hex
    }

    /// Past een geldige HEX-invoer toe. - Returns: `false` bij ongeldige invoer.
    @discardableResult
    func applyHexInput() -> Bool {
        guard isHexInputValid else { return false }
        let color = HexColor(hexInput)
        draft[selectedField] = color
        selectedHSB = HSBColor(color)
        hexInput = color.hex
        return true
    }

    // MARK: - Acties

    /// Vervangt alle kleuren door een palet rond de huidige accentkleur.
    func generateFromAccent(dark: Bool) {
        let generated = ThemePaletteGenerator.generated(fromAccent: draft[.accent], dark: dark, id: draft.id, name: draft.name)
        draft = generated
        syncSelection()
    }

    /// Past tekst-, accent- en winst/verlieskleuren aan tot ze WCAG AA halen.
    func autoCorrectContrast() {
        draft = ThemePaletteGenerator.autoCorrected(draft)
        syncSelection()
    }

    /// Terug naar de kleuren van het standaardthema (naam en id blijven).
    func resetColors() {
        draft = CustomTheme(id: draft.id, name: draft.name, basedOn: .standard)
        syncSelection()
    }

    func save(to store: ThemeStore) {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        store.save(draft)
    }

    private func syncSelection() {
        selectedHSB = HSBColor(draft[selectedField])
        hexInput = draft[selectedField].hex
    }
}
