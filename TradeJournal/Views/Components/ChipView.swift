import SwiftUI

/// Herbruikbare selecteerbare chip, gebruikt voor confluences, tags en
/// fouten in het tradeformulier en tradedetail.
struct ChipView: View {

    let title: String
    var systemImage: String?
    var color: Color = Theme.accent
    let isSelected: Bool
    /// `nil` maakt de chip niet-interactief (alleen-lezen weergave, zoals in tradedetail).
    var action: (() -> Void)? = nil

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(Theme.textPrimary)
            .background(isSelected ? color.opacity(0.85) : Theme.elevated)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(color.opacity(isSelected ? 0 : 0.35), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var content: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption)
            }
            Text(title)
                .font(.subheadline.weight(.medium))
        }
    }
}

#Preview {
    HStack {
        ChipView(title: "Sweep PDL", systemImage: "arrow.down.right", color: Theme.accent, isSelected: true) {}
        ChipView(title: "IFVG", color: Theme.profit, isSelected: false) {}
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
