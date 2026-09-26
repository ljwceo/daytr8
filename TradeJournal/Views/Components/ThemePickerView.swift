import SwiftUI

/// Kleurstalen per groep (Pastel / Effen) met een live preview erboven.
/// Een tik kiest het thema meteen voor de hele app (en bewaart de keuze).
/// Gebruikt in Meer → Thema en in de onboarding.
struct ThemePickerView: View {

    var store: ThemeStore = .shared

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ThemePreviewCardView(palette: store.palette)

            ForEach(ThemePalette.Group.allCases) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(ThemePalette.palettes(in: group)) { palette in
                            swatch(palette)
                        }
                    }
                }
            }
        }
    }

    private func swatch(_ palette: ThemePalette) -> some View {
        let isSelected = palette == store.palette
        return Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                store.select(palette)
            }
        } label: {
            VStack(spacing: 6) {
                VStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(palette.card.color)
                        .frame(height: 14)
                    HStack(spacing: 5) {
                        Circle().fill(palette.profit.color)
                        Circle().fill(palette.loss.color)
                        Circle().fill(palette.accent.color)
                    }
                    .frame(height: 12)
                }
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(palette.background.color)
                .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                        .stroke(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 3 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.accent)
                            .background(Circle().fill(Theme.background))
                            .offset(x: 6, y: -6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                Text(palette.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(palette.name)
        .accessibilityValue(isSelected ? AppStrings.Themes.selectedAccessibility : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Mini-dashboard in de kleuren van `palette`: dagresultaat, twee trades
/// (winst en verlies) en een primaire knop.
struct ThemePreviewCardView: View {

    let palette: ThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.Themes.preview.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.textTertiary.color)

            HStack(alignment: .firstTextBaseline) {
                Text(AppStrings.Themes.previewAccount)
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary.color)
                Spacer()
                Text("+$482")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(palette.profit.color)
            }

            previewRow(symbol: "NQ", side: "Long", label: AppStrings.Themes.previewWin, amount: "+$620", color: palette.profit)
            previewRow(symbol: "ES", side: "Short", label: AppStrings.Themes.previewLoss, amount: "-$138", color: palette.loss)

            Text(AppStrings.Themes.previewButton)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.onAccent.color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(palette.accent.color)
                .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
        }
        .padding(Theme.cardPadding)
        .background(palette.background.color)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(palette.textPrimary.color.opacity(palette.borderOpacity), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private func previewRow(symbol: String, side: String, label: String, amount: String, color: HexColor) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.textPrimary.color)
                Text(side)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary.color)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(amount)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(color.color)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(palette.textTertiary.color)
            }
        }
        .padding(10)
        .background(palette.card.color)
        .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
    }
}

#Preview {
    ScrollView {
        ThemePickerView(store: ThemeStore(defaults: UserDefaults(suiteName: "preview")!))
            .padding()
    }
    .background(Theme.background)
}
