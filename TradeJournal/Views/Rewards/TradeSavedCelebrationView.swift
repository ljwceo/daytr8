import SwiftUI

/// Korte animatie na het opslaan van een nieuwe trade (max. ~1,5 s):
/// een oplichtend succesvinkje op een kaartje dat daarna richting de
/// Rapporten-tab "wegvliegt". Bij 3+ winsten op rij een hot streak met
/// vlammen en gloed; hoe langer de streak, hoe feller.
///
/// - Alleen transforms en opacity (plus een `Canvas` voor de deeltjes), dus
///   soepel op 60 fps en zonder layout-werk per frame.
/// - Een tik ergens slaat de animatie over.
/// - Met "Verminder beweging" alleen een korte fade, zonder vliegen of deeltjes.
struct TradeSavedCelebrationView: View {

    let celebration: RewardsViewModel.Celebration
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase { case hidden, shown, flying }

    @State private var phase: Phase = .hidden
    @State private var ringExpanded = false
    @State private var isFinished = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.background
                    .opacity(phase == .shown ? 0.6 : 0)
                    .ignoresSafeArea()

                if celebration.isHotStreak && !reduceMotion {
                    HotStreakParticlesView(intensity: celebration.intensity)
                        .opacity(phase == .shown ? 1 : 0)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                card
                    .scaleEffect(cardScale)
                    .offset(cardOffset(in: proxy.size))
                    .opacity(phase == .shown ? 1 : 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task { await run() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(AppStrings.Rewards.skipHint)
    }

    // MARK: - Kaart

    private var card: some View {
        VStack(spacing: 12) {
            checkmark

            Text(AppStrings.Rewards.tradeSaved)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            if celebration.outcome != .open {
                Text(celebration.netPnL.formatted(.currency(code: celebration.currency)))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.color(forPnL: celebration.netPnL))
            }

            if celebration.isHotStreak {
                hotStreakBadge
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(minWidth: 220)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(celebration.isHotStreak ? streakColors[1].opacity(0.7) : Theme.border, lineWidth: celebration.isHotStreak ? 2 : 1)
        )
        .shadow(color: celebration.isHotStreak ? streakColors[1].opacity(0.25 + 0.35 * celebration.intensity) : Theme.shadow,
                radius: celebration.isHotStreak ? 18 + 18 * celebration.intensity : 16)
    }

    private var checkmark: some View {
        ZStack {
            // Uitdijende ring: het vinkje "licht op".
            Circle()
                .stroke(accentColor.opacity(ringExpanded ? 0 : 0.6), lineWidth: 3)
                .scaleEffect(ringExpanded ? 1.7 : 1)
            Circle()
                .fill(accentColor)
                .shadow(color: accentColor.opacity(phase == .shown ? 0.7 : 0), radius: phase == .shown ? 14 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(onAccentColor)
                .scaleEffect(phase == .shown ? 1 : 0.3)
        }
        .frame(width: 64, height: 64)
    }

    private var hotStreakBadge: some View {
        let size = 1 + 0.35 * celebration.intensity
        return HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .foregroundStyle(LinearGradient(colors: streakColors, startPoint: .bottom, endPoint: .top))
                .scaleEffect(size)
            Text(AppStrings.Rewards.hotStreak(celebration.winStreak))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(streakColors[1].opacity(0.15 + 0.15 * celebration.intensity))
        )
        .overlay(Capsule().stroke(streakColors[1].opacity(0.6), lineWidth: 1))
    }

    // MARK: - Kleuren

    /// Succes: groen bij winst, anders het accent.
    private var accentColor: Color {
        celebration.outcome == .win ? Theme.profit : Theme.accent
    }

    private var onAccentColor: Color {
        celebration.outcome == .win ? Theme.background : Theme.onAccent
    }

    private var streakColors: [Color] {
        Theme.hotStreakColors(intensity: celebration.intensity)
    }

    // MARK: - Beweging

    private var cardScale: CGFloat {
        if reduceMotion { return 1 }
        switch phase {
        case .hidden: return 0.7
        case .shown: return 1
        case .flying: return 0.15
        }
    }

    /// Bij het wegvliegen: naar de Rapporten-tab (4e van 5 tabs, onderin).
    private func cardOffset(in size: CGSize) -> CGSize {
        guard phase == .flying, !reduceMotion else { return .zero }
        let tabIndex = Double(AppTab.allCases.firstIndex(of: .reports) ?? 3)
        let tabCount = Double(AppTab.allCases.count)
        let x = size.width * ((tabIndex + 0.5) / tabCount - 0.5)
        return CGSize(width: x, height: size.height * 0.5)
    }

    private var holdDuration: Duration {
        celebration.isHotStreak ? .milliseconds(750) : .milliseconds(550)
    }

    @MainActor
    private func run() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { phase = .shown }
            try? await Task.sleep(for: .milliseconds(800))
            guard !isFinished else { return }
            withAnimation(.easeIn(duration: 0.2)) { phase = .hidden }
            try? await Task.sleep(for: .milliseconds(200))
            finish()
            return
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) { phase = .shown }
        withAnimation(.easeOut(duration: 0.7).delay(0.15)) { ringExpanded = true }
        try? await Task.sleep(for: .milliseconds(350))
        try? await Task.sleep(for: holdDuration)
        guard !isFinished else { return }

        withAnimation(.easeIn(duration: 0.35)) { phase = .flying }
        try? await Task.sleep(for: .milliseconds(350))
        finish()
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        onFinished()
    }
}

/// Opstijgende vlammetjes/vonken voor de hot streak. Aantal, grootte en
/// snelheid groeien met `intensity` (0…1). Getekend in één `Canvas` per frame.
struct HotStreakParticlesView: View {

    let intensity: Double

    @State private var start = Date()

    private struct Particle {
        let x: Double
        let phase: Double
        let speed: Double
        let size: Double
        let wobble: Double
        let isFlame: Bool
    }

    private var particles: [Particle] {
        let count = 10 + Int(30 * intensity)
        return (0..<count).map { index in
            // Deterministische "willekeur": geen state nodig per frame.
            func noise(_ seed: Double) -> Double {
                let value = sin(Double(index) * 12.9898 + seed * 78.233) * 43758.5453
                return value - value.rounded(.down)
            }
            return Particle(
                x: 0.1 + 0.8 * noise(1),
                phase: noise(2),
                speed: 0.45 + 0.35 * noise(3) + 0.3 * intensity,
                size: (14 + 14 * noise(4)) * (1 + 0.6 * intensity),
                wobble: 1 + 2 * noise(5),
                isFlame: noise(6) < 0.6
            )
        }
    }

    var body: some View {
        let particles = self.particles
        let colors = Theme.hotStreakColors(intensity: intensity)
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                guard let flame = context.resolveSymbol(id: 0),
                      let spark = context.resolveSymbol(id: 1) else { return }
                for particle in particles {
                    let t = (elapsed * particle.speed + particle.phase).truncatingRemainder(dividingBy: 1)
                    let x = particle.x * size.width + sin(t * .pi * 2 * particle.wobble) * 14
                    let y = size.height * (1.05 - t * 0.9)
                    var copy = context
                    copy.opacity = (1 - t) * (0.55 + 0.45 * intensity)
                    let scale = particle.size / 24 * (1 - 0.4 * t)
                    copy.translateBy(x: x, y: y)
                    copy.scaleBy(x: scale, y: scale)
                    copy.draw(particle.isFlame ? flame : spark, at: .zero)
                }
            } symbols: {
                Image(systemName: "flame.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                    .tag(0)
                Circle()
                    .fill(colors[1])
                    .frame(width: 8, height: 8)
                    .tag(1)
            }
        }
        .background(
            RadialGradient(
                colors: [colors[1].opacity(0.25 + 0.3 * intensity), .clear],
                center: .bottom,
                startRadius: 0,
                endRadius: 420 + 200 * intensity
            )
        )
    }
}

#Preview {
    TradeSavedCelebrationView(
        celebration: .init(outcome: .win, netPnL: 420, currency: "USD", winStreak: 7),
        onFinished: {}
    )
}
