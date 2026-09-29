import XCTest
@testable import TradeJournal

/// Eigen thema's: kleurwiskunde (HSB/HEX), contrastcorrectie, paletgenerator
/// en opslag in `ThemeStore`.
final class CustomThemeTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "CustomThemeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Kleurwiskunde

    func test_hexValidation() {
        XCTAssertTrue(HexColor.isValidHex("#5AB0FF"))
        XCTAssertTrue(HexColor.isValidHex("5ab0ff"))
        XCTAssertFalse(HexColor.isValidHex("#5AB0F"))
        XCTAssertFalse(HexColor.isValidHex("#GGGGGG"))
        XCTAssertFalse(HexColor.isValidHex(""))
    }

    func test_hsbRoundTrip() {
        for hex in ["#FF0000", "#00FF00", "#0000FF", "#5AB0FF", "#34D17F", "#17191D", "#FFFFFF", "#000000", "#8A5A00"] {
            let color = HexColor(hex)
            XCTAssertEqual(HSBColor(color).hexColor, color, hex)
        }
    }

    func test_hsbKnownValues() {
        let red = HSBColor(HexColor("#FF0000"))
        XCTAssertEqual(red.hue, 0, accuracy: 0.001)
        XCTAssertEqual(red.saturation, 1, accuracy: 0.001)
        XCTAssertEqual(red.brightness, 1, accuracy: 0.001)

        let blue = HSBColor(HexColor("#0000FF"))
        XCTAssertEqual(blue.hue, 2.0 / 3.0, accuracy: 0.001)

        XCTAssertEqual(HSBColor(hue: 1.25, saturation: 2, brightness: -1).hue, 0.25, accuracy: 0.0001)
        XCTAssertEqual(HSBColor(hue: -0.25, saturation: 0.5, brightness: 0.5).hue, 0.75, accuracy: 0.0001)
    }

    func test_mixed() {
        XCTAssertEqual(HexColor.black.mixed(with: .white, amount: 0), .black)
        XCTAssertEqual(HexColor.black.mixed(with: .white, amount: 1), .white)
        XCTAssertEqual(HexColor.black.mixed(with: .white, amount: 0.5), HexColor("#808080"))
    }

    func test_ensuringContrast_reachesMinimum() {
        let surfaces = [HexColor("#17191D"), HexColor("#22252B")]
        let dim = HexColor("#333842")
        XCTAssertLessThan(dim.minimumContrast(on: surfaces), 4.5)
        let fixed = dim.ensuringContrast(on: surfaces, minimum: 4.5)
        XCTAssertGreaterThanOrEqual(fixed.minimumContrast(on: surfaces), 4.5)

        // Al goed → ongewijzigd.
        let good = HexColor("#F2F3F5")
        XCTAssertEqual(good.ensuringContrast(on: surfaces, minimum: 4.5), good)
    }

    // MARK: - Palet

    func test_customTheme_fromBuiltInPalette_matchesItsColors() {
        let theme = CustomTheme(name: "Kopie", basedOn: .donker)
        let palette = theme.palette
        XCTAssertEqual(palette.background, ThemePalette.donker.background)
        XCTAssertEqual(palette.card, ThemePalette.donker.card)
        XCTAssertEqual(palette.textPrimary, ThemePalette.donker.textPrimary)
        XCTAssertEqual(palette.accent, ThemePalette.donker.accent)
        XCTAssertEqual(palette.profit, ThemePalette.donker.profit)
        XCTAssertEqual(palette.loss, ThemePalette.donker.loss)
        XCTAssertTrue(palette.isDark)
        XCTAssertEqual(palette.group, .custom)
        XCTAssertTrue(ThemePaletteGenerator.contrastIssues(for: theme).isEmpty)
    }

    func test_generatedPalettes_meetWCAGAA() {
        let accents = ["#5AB0FF", "#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FF00FF", "#FFFFFF", "#000000", "#808080", "#FFA500", "#8A2BE2", "#2E8B57"]
        for accent in accents {
            for dark in [true, false] {
                let theme = ThemePaletteGenerator.generated(fromAccent: HexColor(accent), dark: dark, id: "custom-test", name: "Test")
                let palette = theme.palette
                XCTAssertEqual(palette.isDark, dark, "\(accent) dark=\(dark)")
                assertMeetsWCAG(palette, label: "\(accent) dark=\(dark)")
            }
        }
    }

    func test_contrastIssues_detectedAndAutoCorrected() {
        var theme = CustomTheme(name: "Slecht", basedOn: .donker)
        theme.text = "#2A2D33"      // bijna gelijk aan de kaart
        theme.loss = "#3A1A1C"
        let issues = ThemePaletteGenerator.contrastIssues(for: theme)
        XCTAssertEqual(Set(issues.map(\.field)), [.text, .loss])

        let corrected = ThemePaletteGenerator.autoCorrected(theme)
        XCTAssertTrue(ThemePaletteGenerator.contrastIssues(for: corrected).isEmpty)
        XCTAssertEqual(corrected.background, theme.background, "achtergrond blijft staan")
        XCTAssertEqual(corrected.card, theme.card, "kaart blijft staan")
        XCTAssertEqual(corrected.accent, theme.accent, "goede kleuren blijven staan")
        assertMeetsWCAG(corrected.palette, label: "gecorrigeerd")
    }

    func test_customTheme_codableRoundTrip() throws {
        let theme = ThemePaletteGenerator.generated(fromAccent: HexColor("#7B61FF"), dark: true, id: "custom-1", name: "Paars")
        let data = try JSONEncoder().encode([theme])
        XCTAssertEqual(try JSONDecoder().decode([CustomTheme].self, from: data), [theme])
    }

    // MARK: - Opslag

    func test_saveSelectsAndPersists() {
        let store = ThemeStore(defaults: defaults)
        let theme = CustomTheme(name: "Mijn thema", basedOn: .mint)
        store.save(theme)

        XCTAssertEqual(store.customThemes, [theme])
        XCTAssertEqual(store.palette.id, theme.id)
        XCTAssertEqual(store.selectedCustomTheme, theme)

        // "Herstart".
        let restarted = ThemeStore(defaults: defaults)
        XCTAssertEqual(restarted.customThemes, [theme])
        XCTAssertEqual(restarted.palette, theme.palette)
    }

    func test_editingActiveTheme_updatesPaletteLive() {
        let store = ThemeStore(defaults: defaults)
        var theme = CustomTheme(name: "A", basedOn: .donker)
        store.save(theme)
        theme.accent = "#FFBF3C"
        theme.name = "B"
        store.save(theme, select: false)
        XCTAssertEqual(store.palette.accent, HexColor("#FFBF3C"))
        XCTAssertEqual(store.palette.name, "B")
        XCTAssertEqual(store.customThemes.count, 1)
    }

    func test_editingInactiveTheme_keepsSelection() {
        let store = ThemeStore(defaults: defaults)
        let theme = CustomTheme(name: "A", basedOn: .donker)
        store.save(theme, select: false)
        XCTAssertEqual(store.palette, .standard)
        store.select(.licht)
        store.save(theme, select: false)
        XCTAssertEqual(store.palette, .licht)
    }

    func test_deleteActiveTheme_fallsBackToStandard() {
        let store = ThemeStore(defaults: defaults)
        let first = CustomTheme(name: "Een", basedOn: .donker)
        let second = CustomTheme(name: "Twee", basedOn: .licht)
        store.save(first)
        store.save(second)
        store.deleteCustomTheme(id: second.id)

        XCTAssertEqual(store.customThemes, [first])
        XCTAssertEqual(store.palette, .standard)
        XCTAssertEqual(ThemeStore(defaults: defaults).customThemes, [first])
    }

    func test_resetToStandard_keepsCustomThemes() {
        let store = ThemeStore(defaults: defaults)
        let theme = CustomTheme(name: "Een", basedOn: .perzik)
        store.save(theme)
        store.resetToStandard()
        XCTAssertEqual(store.palette, .standard)
        XCTAssertEqual(store.customThemes, [theme])
    }

    func test_reload_picksUpRestoredThemes() {
        let store = ThemeStore(defaults: defaults)
        let other = ThemeStore(defaults: defaults)
        let theme = CustomTheme(name: "Uit backup", basedOn: .bosgroen)
        other.save(theme)

        XCTAssertTrue(store.customThemes.isEmpty)
        store.reload()
        XCTAssertEqual(store.customThemes, [theme])
        XCTAssertEqual(store.palette.id, theme.id)
    }

    func test_customThemeKeys_areBackedUp() {
        XCTAssertTrue(SettingsMigrator.backedUpKeys.contains(ThemeStore.Keys.customThemes))
        XCTAssertTrue(SettingsMigrator.backedUpKeys.contains(ThemeStore.Keys.selectedPaletteID))
    }

    // MARK: - Editor

    func test_editor_hexInputAndWheel() {
        let viewModel = ThemeEditorViewModel(theme: nil, basedOn: .donker)
        XCTAssertTrue(viewModel.isNew)
        XCTAssertEqual(viewModel.selectedField, .accent)

        viewModel.select(.profit)
        viewModel.hexInput = "#12AB34"
        XCTAssertTrue(viewModel.applyHexInput())
        XCTAssertEqual(viewModel.draft.profit, "#12AB34")

        viewModel.hexInput = "nope"
        XCTAssertFalse(viewModel.applyHexInput())
        XCTAssertEqual(viewModel.draft.profit, "#12AB34")

        viewModel.select(.accent)
        viewModel.updateSelectedColor(HSBColor(hue: 0, saturation: 1, brightness: 1))
        XCTAssertEqual(viewModel.draft.accent, "#FF0000")
        XCTAssertEqual(viewModel.hexInput, "#FF0000")
    }

    func test_editor_generateAndSave() {
        let store = ThemeStore(defaults: defaults)
        let viewModel = ThemeEditorViewModel(theme: nil, basedOn: store.palette)
        viewModel.draft.name = "  Oranje  "
        viewModel.select(.accent)
        viewModel.hexInput = "#FF8A00"
        viewModel.applyHexInput()
        viewModel.generateFromAccent(dark: false)
        XCTAssertFalse(viewModel.palette.isDark)
        XCTAssertTrue(viewModel.contrastIssues.isEmpty)

        viewModel.save(to: store)
        XCTAssertEqual(store.customThemes.first?.name, "Oranje")
        XCTAssertEqual(store.palette.id, viewModel.draft.id)
    }

    func test_editor_emptyNameCannotSave() {
        let viewModel = ThemeEditorViewModel(theme: nil, basedOn: .donker)
        viewModel.draft.name = "   "
        XCTAssertFalse(viewModel.canSave)
    }

    // MARK: - Helpers

    private func assertMeetsWCAG(_ palette: ThemePalette, label: String, file: StaticString = #filePath, line: UInt = #line) {
        for surface in palette.surfaces {
            for (name, color) in [("textPrimary", palette.textPrimary), ("textSecondary", palette.textSecondary),
                                  ("accent", palette.accent), ("profit", palette.profit), ("loss", palette.loss)] {
                let ratio = HexColor.contrastRatio(color, surface)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(label): \(name) op \(surface.hex) = \(ratio)", file: file, line: line)
            }
            for (name, color) in [("textTertiary", palette.textTertiary), ("neutral", palette.neutral), ("warning", palette.warning)] {
                let ratio = HexColor.contrastRatio(color, surface)
                XCTAssertGreaterThanOrEqual(ratio, 3, "\(label): \(name) op \(surface.hex) = \(ratio)", file: file, line: line)
            }
        }
        XCTAssertGreaterThanOrEqual(HexColor.contrastRatio(palette.onAccent, palette.accent), 4.5, "\(label): onAccent", file: file, line: line)
    }
}
