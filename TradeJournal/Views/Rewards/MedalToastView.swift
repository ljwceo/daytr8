import SwiftUI

/// Melding bovenin bij een nieuw behaalde medaille (of een samenvatting).
/// Tikken opent het medaille-overzicht; omhoog vegen sluit hem.
struct MedalToastView: View {

    let toast: RewardsViewModel.Toast
    let onOpen: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                icon
                    .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.4)
                    .rotationEffect(.degrees(hasAppeared || reduceMotion ? 0 : -40))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Text(AppStrings.Rewards.toastHint)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(12)
            .background(Theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .shadow(color: Theme.shadow, radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.height < -20 { onDismiss() }
            }
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.1)) {
                hasAppeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(AppStrings.Rewards.toastHint)
    }

    @ViewBuilder
    private var icon: some View {
        switch toast {
        case .medal(let definition, _):
            MedalIconView(definition: definition, size: 44)
        case .summary:
            Image(systemName: "rosette")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.accent))
        }
    }

    private var title: String {
        switch toast {
        case .medal: return AppStrings.Rewards.toastTitle
        case .summary(_, let isInitial): return isInitial ? AppStrings.Rewards.summaryInitialTitle : AppStrings.Rewards.summaryTitle
        }
    }

    private var message: String {
        switch toast {
        case .medal(let definition, _): return definition.name
        case .summary(let count, _): return AppStrings.Rewards.summaryMessage(count)
        }
    }

    private var borderColor: Color {
        switch toast {
        case .medal(let definition, _): return Theme.medalGradient(definition.tier)[0].opacity(0.8)
        case .summary: return Theme.accent.opacity(0.6)
        }
    }
}
