import SwiftUI

/// Meer → Thema: kleurstalen met live preview. De keuze wordt direct
/// toegepast en bewaard (`ThemeStore`). Eigen thema's maken, bewerken en
/// verwijderen gaat via de editor in een sheet (`ThemeEditorView`), zodat
/// dit scherm zelf compact blijft.
struct ThemeSettingsView: View {

    var store: ThemeStore = .shared

    /// Item voor de editor-sheet: `nil`-thema = nieuw.
    private struct EditorTarget: Identifiable {
        let id = UUID()
        let theme: CustomTheme?
    }

    @State private var editorTarget: EditorTarget?
    @State private var themeToDelete: CustomTheme?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ThemePickerView(store: store) {
                    editorTarget = EditorTarget(theme: nil)
                }

                if !store.customThemes.isEmpty {
                    customThemesCard
                }

                if store.palette != .standard {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) { store.resetToStandard() }
                    } label: {
                        Label(AppStrings.Themes.resetToStandard, systemImage: "arrow.counterclockwise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }

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
        .sheet(item: $editorTarget) { target in
            ThemeEditorView(theme: target.theme, store: store)
        }
        .confirmationDialog(
            AppStrings.Themes.deleteConfirm(themeToDelete?.name ?? ""),
            isPresented: Binding(get: { themeToDelete != nil }, set: { if !$0 { themeToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(AppStrings.Themes.editorDelete, role: .destructive) {
                if let theme = themeToDelete {
                    withAnimation { store.deleteCustomTheme(id: theme.id) }
                }
                themeToDelete = nil
            }
            Button("Annuleren", role: .cancel) { themeToDelete = nil }
        }
    }

    /// Compacte lijst van eigen thema's met bewerken en verwijderen.
    private var customThemesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.Themes.manageCustom.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)

            ForEach(store.customThemes) { theme in
                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        ForEach([CustomTheme.Field.background, .card, .accent, .profit, .loss]) { field in
                            Circle()
                                .fill(theme[field].color)
                                .frame(width: 12, height: 12)
                        }
                    }
                    .padding(5)
                    .background(Capsule().fill(Theme.elevated))

                    Text(theme.name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if store.palette.id == theme.id {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer(minLength: 0)
                    Button {
                        editorTarget = EditorTarget(theme: theme)
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(Theme.accent)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(AppStrings.Themes.editTheme): \(theme.name)")
                    Button {
                        themeToDelete = theme
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Theme.loss)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(AppStrings.Themes.editorDelete): \(theme.name)")
                }
            }

            Text(AppStrings.Themes.manageCustomFooter)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        ThemeSettingsView()
    }
}
