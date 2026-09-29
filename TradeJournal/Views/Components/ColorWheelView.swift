import SwiftUI

/// Kleurenwiel: hoek = tint (hue), afstand tot het midden = verzadiging.
/// De helderheid dimt het hele wiel (in te stellen met een aparte slider).
/// Slepen of tikken kiest een kleur.
struct ColorWheelView: View {

    @Binding var color: HSBColor

    private static let hueStops: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
        Color(hue: $0, saturation: 1, brightness: 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side / 2
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                Circle()
                    .fill(AngularGradient(colors: Self.hueStops, center: .center))
                Circle()
                    .fill(RadialGradient(
                        colors: [Theme.colorWheelWhite, Theme.colorWheelWhite.opacity(0)],
                        center: .center, startRadius: 0, endRadius: radius
                    ))
                Circle()
                    .fill(Theme.colorWheelBlack.opacity(1 - color.brightness))
                Circle()
                    .stroke(Theme.border, lineWidth: 1)
            }
            .frame(width: side, height: side)
            .position(center)
            .overlay {
                Circle()
                    .fill(color.hexColor.color)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Theme.colorWheelWhite, lineWidth: 3))
                    .shadow(color: Theme.shadow, radius: 3)
                    .position(knobPosition(center: center, radius: radius))
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        select(at: value.location, center: center, radius: radius)
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Kleurenwiel")
        .accessibilityValue("Tint \(Int(color.hue * 360)) graden, verzadiging \(Int(color.saturation * 100)) procent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: color.hue = (color.hue + 1.0 / 36).truncatingRemainder(dividingBy: 1)
            case .decrement: color.hue = (color.hue - 1.0 / 36 + 1).truncatingRemainder(dividingBy: 1)
            @unknown default: break
            }
        }
    }

    private func knobPosition(center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = CGFloat(color.hue) * 2 * .pi
        let distance = CGFloat(color.saturation) * radius
        return CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
    }

    private func select(at location: CGPoint, center: CGPoint, radius: CGFloat) {
        guard radius > 0 else { return }
        let dx = location.x - center.x
        let dy = location.y - center.y
        var angle = atan2(dy, dx)
        if angle < 0 { angle += 2 * .pi }
        let distance = min(sqrt(dx * dx + dy * dy) / radius, 1)
        color = HSBColor(hue: Double(angle / (2 * .pi)), saturation: Double(distance), brightness: color.brightness)
    }
}
