import SwiftUI

/// In-app welkomstmelding in de stijl van een pushmelding, bovenin het
/// scherm bij de eerste start. Tikken opent de rondleiding; het kruisje of
/// omhoog vegen sluit de melding. Geen systeemnotificatie, dus geen toestemming nodig.
struct WelcomeBannerView: View {

    let onOpen: () -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onOpen) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 38, height: 38)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppStrings.Welcome.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(AppStrings.Welcome.message)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.Welcome.closeAccessibility)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Theme.elevated)
                .shadow(color: Theme.shadow, radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .offset(y: min(dragOffset, 0))
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { dragOffset = $0.translation.height }
                .onEnded { value in
                    if value.translation.height < -30 {
                        onDismiss()
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                    }
                }
        )
    }
}

#Preview {
    VStack {
        WelcomeBannerView(onOpen: {}, onDismiss: {})
            .padding()
        Spacer()
    }
    .background(Theme.background)
}
