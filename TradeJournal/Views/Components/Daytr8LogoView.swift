import SwiftUI

/// De gestileerde "8" van het Daytr8-logo: twee gestapelde lussen (de
/// onderste iets breder) met twee scherpe hoeken — linksboven en
/// rechtsonder — als kenmerk; de rest is afgerond. Een vectorvorm, dus scherp
/// op elk formaat, van 24 pt in een toolbar tot het app-icoon.
///
/// Geometrie in een kader van 100 × 140; dezelfde maten staan in
/// `Branding/generate_icons.py` en de SVG's in `Branding/`.
struct Daytr8EightShape: Shape {

    /// Breedte/hoogte-verhouding van de vorm.
    static let aspectRatio: CGFloat = 100.0 / 140.0

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 100
        let sy = rect.height / 140
        let s = min(sx, sy)
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                 topLeading: CGFloat, topTrailing: CGFloat, bottomTrailing: CGFloat, bottomLeading: CGFloat) -> CGPath {
            let frame = CGRect(x: rect.minX + x * sx, y: rect.minY + y * sy, width: w * sx, height: h * sy)
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: topLeading * s,
                bottomLeadingRadius: bottomLeading * s,
                bottomTrailingRadius: bottomTrailing * s,
                topTrailingRadius: topTrailing * s,
                style: .circular
            )
            return shape.path(in: frame).cgPath
        }

        let top = box(8, 0, 84, 66, topLeading: 0, topTrailing: 30, bottomTrailing: 30, bottomLeading: 30)
        let bottom = box(0, 58, 100, 82, topLeading: 36, topTrailing: 36, bottomTrailing: 0, bottomLeading: 36)
        let topHole = box(32, 22, 36, 22, topLeading: 11, topTrailing: 11, bottomTrailing: 11, bottomLeading: 11)
        let bottomHole = box(28, 82, 44, 36, topLeading: 18, topTrailing: 18, bottomTrailing: 18, bottomLeading: 18)
        return Path(top.union(bottom).subtracting(topHole.union(bottomHole)))
    }
}

/// Het Daytr8-logo in twee varianten:
/// - `.wordmark`: "Daytr" in een zware sans-serif in `Theme.textPrimary`, met
///   de gestileerde "8" in `Theme.accent`;
/// - `.icon`: alleen de "8" (herkenbaar vanaf 24 pt), in `Theme.accent`.
///
/// Kleuren worden in `body` uit `Theme` gelezen, dus het logo volgt een
/// themawissel direct.
struct Daytr8LogoView: View {

    enum Variant {
        case wordmark
        case icon
    }

    var variant: Variant = .wordmark
    /// Wordmark: lettergrootte. Icoon: hoogte van de "8".
    var size: CGFloat = 28
    /// Kleur van de "8"; `nil` = `Theme.accent`. Gebruik `Theme.onAccent`
    /// als het icoon op een accentvlak staat.
    var eightColor: Color? = nil

    var body: some View {
        Group {
            switch variant {
            case .wordmark: wordmark
            case .icon: eight(height: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daytr8")
        .accessibilityAddTraits(.isImage)
    }

    private var wordmark: some View {
        HStack(alignment: .lastTextBaseline, spacing: size * 0.04) {
            Text("Daytr")
                .font(.system(size: size, weight: .black, design: .default))
                .tracking(-size * 0.035)
                .foregroundStyle(Theme.textPrimary)
            // Hoogte van een hoofdletter in SF Pro ≈ 0,72 × lettergrootte.
            eight(height: size * 0.72)
        }
        .fixedSize()
    }

    private func eight(height: CGFloat) -> some View {
        Daytr8EightShape()
            .fill(eightColor ?? Theme.accent)
            .frame(width: height * Daytr8EightShape.aspectRatio, height: height)
    }
}

#Preview {
    VStack(spacing: 24) {
        Daytr8LogoView(variant: .wordmark, size: 40)
        Daytr8LogoView(variant: .wordmark, size: 20)
        HStack(spacing: 16) {
            Daytr8LogoView(variant: .icon, size: 24)
            Daytr8LogoView(variant: .icon, size: 64)
        }
    }
    .padding()
    .background(Theme.background)
}
