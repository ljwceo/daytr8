import XCTest
import SwiftUI
@testable import TradeJournal

@MainActor
final class Daytr8LogoTests: XCTestCase {

    /// WCAG: grafische elementen ≥ 3:1, tekst ≥ 4,5:1.
    func test_logoHasEnoughContrastInEveryTheme() {
        for palette in ThemePalette.all {
            for surface in [palette.background, palette.card] {
                XCTAssertGreaterThanOrEqual(HexColor.contrastRatio(palette.accent, surface), 3,
                                            "\(palette.id): accent-8 op \(surface.hex)")
                XCTAssertGreaterThanOrEqual(HexColor.contrastRatio(palette.textPrimary, surface), 4.5,
                                            "\(palette.id): woordmerk op \(surface.hex)")
            }
            // Icoon op accentvlak (welkomstmelding).
            XCTAssertGreaterThanOrEqual(HexColor.contrastRatio(palette.onAccent, palette.accent), 3, "\(palette.id): 8 op accent")
        }
    }

    /// Statische iconen (app-icoon, favicon) gebruiken de standaardkleuren.
    func test_staticIconColorsAreStandardTheme() {
        XCTAssertEqual(ThemePalette.standard.id, "donker")
        XCTAssertEqual(ThemePalette.standard.background.hex, "#17191D")
        XCTAssertEqual(ThemePalette.standard.accent.hex, "#5AB0FF")
        XCTAssertGreaterThanOrEqual(HexColor.contrastRatio(ThemePalette.standard.accent, ThemePalette.standard.background), 3)
    }

    func test_eightShape_hasHolesAndFilledLoops() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 140)
        let path = Daytr8EightShape().path(in: rect)
        XCTAssertFalse(path.isEmpty)
        XCTAssertEqual(path.boundingRect.width, 100, accuracy: 0.5)
        XCTAssertEqual(path.boundingRect.height, 140, accuracy: 0.5)

        XCTAssertFalse(path.contains(CGPoint(x: 50, y: 33)), "gat boven")
        XCTAssertFalse(path.contains(CGPoint(x: 50, y: 100)), "gat onder")
        XCTAssertFalse(path.contains(CGPoint(x: 50, y: 33), eoFill: true), "gat boven (even-odd, zoals de view vult)")
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 10)), "bovenbalk")
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 62)), "taille")
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 130)), "onderbalk")
        // Kenmerk: scherpe hoeken linksboven en rechtsonder.
        XCTAssertTrue(path.contains(CGPoint(x: 9, y: 1)))
        XCTAssertTrue(path.contains(CGPoint(x: 99, y: 139)))
        XCTAssertFalse(path.contains(CGPoint(x: 1, y: 139)), "linksonder is afgerond")
    }

    func test_eightShape_scalesToSmallSizes() {
        let path = Daytr8EightShape().path(in: CGRect(x: 0, y: 0, width: 24 * Daytr8EightShape.aspectRatio, height: 24))
        XCTAssertFalse(path.isEmpty)
        XCTAssertFalse(path.contains(CGPoint(x: 8.5, y: 5.6)), "gat boven blijft open op 24 pt")
    }
}
