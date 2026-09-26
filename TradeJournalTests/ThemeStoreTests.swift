import XCTest
@testable import TradeJournal

/// Themasysteem: keuze blijft bewaard na herstart en alle paletten halen
/// WCAG AA voor tekst (ook winst/verlies).
final class ThemeStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ThemeStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Opslag

    func test_defaultPalette_onFirstLaunch() {
        XCTAssertEqual(ThemeStore(defaults: defaults).palette, .standard)
        XCTAssertEqual(ThemePalette.standard, .donker)
    }

    func test_selection_persistsAcrossRestart() {
        let store = ThemeStore(defaults: defaults)
        store.select(.mint)
        XCTAssertEqual(store.palette, .mint)

        // "Herstart": nieuwe store op dezelfde defaults.
        XCTAssertEqual(ThemeStore(defaults: defaults).palette, .mint)

        store.select(.middernachtblauw)
        XCTAssertEqual(ThemeStore(defaults: defaults).palette, .middernachtblauw)
    }

    func test_unknownStoredID_fallsBackToStandard() {
        defaults.set("bestaat-niet", forKey: ThemeStore.Keys.selectedPaletteID)
        XCTAssertEqual(ThemeStore(defaults: defaults).palette, .standard)
    }

    // MARK: - Paletten

    func test_allRequestedPalettesExist() {
        XCTAssertEqual(ThemePalette.palettes(in: .pastel).map(\.name), ["Lavendel", "Mint", "Perzik", "Babyblauw"])
        XCTAssertEqual(Set(ThemePalette.palettes(in: .solid).map(\.name)), ["Licht", "Donker", "Middernachtblauw", "Bosgroen"])
        XCTAssertEqual(Set(ThemePalette.all.map(\.id)).count, ThemePalette.all.count, "ids moeten uniek zijn")
    }

    func test_contrastRatio_knownValues() {
        XCTAssertEqual(HexColor.contrastRatio(HexColor("#000000"), HexColor("#FFFFFF")), 21, accuracy: 0.01)
        XCTAssertEqual(HexColor.contrastRatio(HexColor("#FFFFFF"), HexColor("#FFFFFF")), 1, accuracy: 0.001)
        XCTAssertEqual(HexColor.contrastRatio(HexColor("#777777"), HexColor("#FFFFFF")), 4.48, accuracy: 0.01)
    }

    func test_allPalettes_meetWCAGAA() {
        for palette in ThemePalette.all {
            for surface in palette.surfaces {
                let aa: [(String, HexColor)] = [
                    ("textPrimary", palette.textPrimary),
                    ("textSecondary", palette.textSecondary),
                    ("accent", palette.accent),
                    ("profit", palette.profit),
                    ("loss", palette.loss)
                ]
                for (name, color) in aa {
                    let ratio = HexColor.contrastRatio(color, surface)
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(palette.name): \(name) op \(surface.hex) = \(ratio)")
                }
                // Hulptekst, iconen en waarschuwingen: minimaal 3:1 (grote tekst / UI).
                let large: [(String, HexColor)] = [
                    ("textTertiary", palette.textTertiary),
                    ("neutral", palette.neutral),
                    ("warning", palette.warning)
                ]
                for (name, color) in large {
                    let ratio = HexColor.contrastRatio(color, surface)
                    XCTAssertGreaterThanOrEqual(ratio, 3.0, "\(palette.name): \(name) op \(surface.hex) = \(ratio)")
                }
            }
            let onAccent = HexColor.contrastRatio(palette.onAccent, palette.accent)
            XCTAssertGreaterThanOrEqual(onAccent, 4.5, "\(palette.name): onAccent = \(onAccent)")
        }
    }

    func test_profitAndLoss_areDistinguishable() {
        for palette in ThemePalette.all {
            XCTAssertNotEqual(palette.profit, palette.loss)
            // Groen heeft meer groen dan rood, rood meer rood dan groen.
            XCTAssertGreaterThan(palette.profit.green, palette.profit.red, palette.name)
            XCTAssertGreaterThan(palette.loss.red, palette.loss.green, palette.name)
        }
    }
}
