import SwiftUI

/// Kleurstalen per groep (Pastel / Effen / Eigen thema's) met een live
/// preview erboven. Een tik kiest het thema meteen voor de hele app (en
/// bewaart de keuze). Gebruikt in Meer → Thema en in de onboarding.
struct ThemePickerView: View {

    var store: ThemeStore = .shared
    /// Gezet in Meer → Thema: toont een "Nieuw thema"-staal die de editor opent.
    var onCreateCustom: (() -> Void)? = nil

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ThemePreviewCardView(palette: store.palette)

            ForEach(ThemePalette.Group.builtIn) { group in
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

            if !store.customThemes.isEmpty || onCreateCustom != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text(ThemePalette.Group.custom.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(store.customPalettes) { palette in
                            swatch(palette)
                        }
                        if let onCreateCustom {
                            newThemeTile(action: onCreateCustom)
                        }
                    }
                }
            }
        }
    }

    private func newThemeTile(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                            .strokeBorder(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    )
                Text(AppStrings.Themes.newTheme)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    /// Ook een mini-grafiek en medaille tonen (thema-editor), zodat zichtbaar
    /// is dat grafieken en rewards de themakleuren volgen.
    var showsExtras: Bool = false

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

            if showsExtras {
                extrasRow
            }

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

    /// Mini-staafgrafiek in winst/verlies-kleuren plus een medaille-chip.
    private var extrasRow: some View {
        let bars: [Double] = [0.5, -0.3, 0.8, 0.35, -0.55, 1.0, 0.6]
        return HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 4) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, value in
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: 22)
                            .overlay(alignment: .bottom) {
                                if value > 0 {
                                    RoundedRectangle(cornerRadius: 2).fill(palette.profit.color).frame(height: 22 * value)
                                }
                            }
                        Rectangle().fill(palette.textTertiary.color.opacity(0.5)).frame(height: 1)
                        Color.clear
                            .frame(height: 22)
                            .overlay(alignment: .top) {
                                if value < 0 {
                                    RoundedRectangle(cornerRadius: 2).fill(palette.loss.color).frame(height: 22 * -value)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(palette.card.color)
            .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))

            HStack(spacing: 6) {
                Image(systemName: "rosette")
                    .foregroundStyle(palette.accent.color)
                Text("12")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary.color)
                Image(systemName: "flame.fill")
                    .foregroundStyle(palette.warning.color)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(palette.elevated.color)
            .clipShape(Capsule())
        }
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
