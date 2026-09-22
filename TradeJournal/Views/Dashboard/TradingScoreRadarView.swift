import SwiftUI

/// Radar/spider-chart voor de samengestelde trading score (6 assen).
/// Swift Charts heeft geen ingebouwd radar-chart-type, dus deze wordt zelf
/// met `Canvas` getekend.
struct TradingScoreRadarView: View {

    let score: TradingScore
    private let ringCount = 4

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                let radius = size / 2 - 28
                let axes = score.axes

                Canvas { context, _ in
                    drawGrid(context: &context, center: center, radius: radius, axisCount: axes.count)
                    drawPolygon(context: &context, center: center, radius: radius, axes: axes)
                }
                .overlay(labels(center: center, radius: radius, axes: axes))
            }
            .frame(height: 220)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(score.overall.rounded()))")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                Text("/ 100")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func point(center: CGPoint, radius: CGFloat, axisIndex: Int, axisCount: Int, fraction: CGFloat) -> CGPoint {
        // Start bovenaan (-90°), met de klok mee verdeeld over de assen.
        let angle = -CGFloat.pi / 2 + CGFloat(axisIndex) / CGFloat(axisCount) * 2 * .pi
        return CGPoint(
            x: center.x + cos(angle) * radius * fraction,
            y: center.y + sin(angle) * radius * fraction
        )
    }

    private func drawGrid(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, axisCount: Int) {
        guard axisCount > 0 else { return }
        for ring in 1...ringCount {
            let fraction = CGFloat(ring) / CGFloat(ringCount)
            var path = Path()
            for i in 0..<axisCount {
                let p = point(center: center, radius: radius, axisIndex: i, axisCount: axisCount, fraction: fraction)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            context.stroke(path, with: .color(Theme.separator), lineWidth: 1)
        }
        for i in 0..<axisCount {
            var spoke = Path()
            spoke.move(to: center)
            spoke.addLine(to: point(center: center, radius: radius, axisIndex: i, axisCount: axisCount, fraction: 1))
            context.stroke(spoke, with: .color(Theme.separator), lineWidth: 1)
        }
    }

    private func drawPolygon(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, axes: [TradingScoreAxis]) {
        guard !axes.isEmpty else { return }
        var path = Path()
        for (i, axis) in axes.enumerated() {
            let fraction = CGFloat(min(max(axis.score, 0), 100) / 100)
            let p = point(center: center, radius: radius, axisIndex: i, axisCount: axes.count, fraction: fraction)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        context.fill(path, with: .color(Theme.accent.opacity(0.35)))
        context.stroke(path, with: .color(Theme.accent), lineWidth: 2)
    }

    private func labels(center: CGPoint, radius: CGFloat, axes: [TradingScoreAxis]) -> some View {
        ForEach(Array(axes.enumerated()), id: \.offset) { index, axis in
            let p = point(center: center, radius: radius + 18, axisIndex: index, axisCount: axes.count, fraction: 1)
            Text(axis.label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(width: 72)
                .position(p)
        }
    }
}

#Preview {
    TradingScoreRadarView(score: TradingScore(winRate: 62, profitFactor: 80, avgWinLossRatio: 55, consistency: 70, drawdown: 90, ruleAdherence: 75))
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.dark)
}
