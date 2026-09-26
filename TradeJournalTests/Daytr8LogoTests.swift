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
        let outline = Daytr8EightShape(part: .outline).path(in: rect)
        XCTAssertEqual(outline.boundingRect.width, 100, accuracy: 0.5)
        XCTAssertEqual(outline.boundingRect.height, 140, accuracy: 0.5)
        func ink(_ x: CGFloat, _ y: CGFloat) -> Bool { Daytr8EightShape.isInk(at: CGPoint(x: x, y: y), in: rect) }

        XCTAssertFalse(ink(50, 33), "gat boven")
        XCTAssertFalse(ink(50, 100), "gat onder")
        XCTAssertTrue(ink(50, 10), "bovenbalk")
        XCTAssertTrue(ink(50, 62), "taille")
        XCTAssertTrue(ink(50, 130), "onderbalk")
        XCTAssertTrue(ink(15, 100), "linkerzijde onder")
        // Kenmerk: scherpe hoeken linksboven en rechtsonder.
        XCTAssertTrue(ink(9, 1))
        XCTAssertTrue(ink(99, 139))
        XCTAssertFalse(ink(1, 139), "linksonder is afgerond")
    }

    func test_eightShape_scalesToSmallSizes() {
        let rect = CGRect(x: 0, y: 0, width: 24 * Daytr8EightShape.aspectRatio, height: 24)
        XCTAssertFalse(Daytr8EightShape.isInk(at: CGPoint(x: 8.5, y: 5.6), in: rect), "gat boven blijft open op 24 pt")
        XCTAssertTrue(Daytr8EightShape.isInk(at: CGPoint(x: 8.5, y: 1.5), in: rect), "bovenbalk zichtbaar op 24 pt")
    }
}
