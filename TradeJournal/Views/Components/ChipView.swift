import SwiftUI

/// Herbruikbare selecteerbare chip, gebruikt voor confluences, tags en
/// fouten in het tradeformulier en tradedetail.
struct ChipView: View {

    let title: String
    var systemImage: String?
    var color: Color = Theme.accent
    /// Tekstkleur als de chip geselecteerd is; `nil` = `Theme.textPrimary`.
    /// Geef `Theme.onAccent` mee bij accent-chips, zodat de tekst in elk thema leesbaar blijft.
    var selectedForeground: Color? = nil
    let isSelected: Bool
    /// `nil` maakt de chip niet-interactief (alleen-lezen weergave, zoals in tradedetail).
    var action: (() -> Void)? = nil

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? (selectedForeground ?? Theme.textPrimary) : Theme.textPrimary)
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
        ChipView(title: "Sweep PDL", systemImage: "arrow.down.right", color: Theme.accent, selectedForeground: Theme.onAccent, isSelected: true) {}
        ChipView(title: "IFVG", color: Theme.profit, isSelected: false) {}
    }
    .padding()
    .background(Theme.background)
}
