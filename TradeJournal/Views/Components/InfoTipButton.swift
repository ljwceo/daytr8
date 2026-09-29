import SwiftUI

/// Klein ⓘ-knopje met een korte uitleg in een popover (ook op iPhone als
/// popover, niet als sheet). Houdt labels in instellingen kort.
struct InfoTipButton: View {

    let text: String

    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Uitleg")
        .accessibilityHint(text)
        .popover(isPresented: $isShowing) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
                .padding(12)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Theme.elevated)
        }
    }
}
