import SwiftUI

/// Meer → Thema: kleurstalen met live preview. De keuze wordt direct
/// toegepast en bewaard (`ThemeStore`).
struct ThemeSettingsView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ThemePickerView()

                Label(AppStrings.Themes.previewFooter, systemImage: "checkmark.shield")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(Theme.cardPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(AppStrings.Themes.settingsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        ThemeSettingsView()
    }
}
