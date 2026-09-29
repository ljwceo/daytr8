import SwiftUI

/// Compacte editor voor een eigen thema, als sheet vanuit Meer → Thema:
/// naam, live preview, kleurenwiel met helderheid/verzadiging en HEX-veld,
/// contrastwaarschuwingen met automatische correctie, palet genereren uit
/// het accent en terugzetten naar de standaardkleuren.
struct ThemeEditorView: View {

    @Environment(\.dismiss) private var dismiss

    var store: ThemeStore = .shared

    @State private var viewModel: ThemeEditorViewModel
    @State private var confirmDelete = false
    @FocusState private var isHexFocused: Bool

    init(theme: CustomTheme?, store: ThemeStore = .shared) {
        self.store = store
        _viewModel = State(initialValue: ThemeEditorViewModel(theme: theme, basedOn: store.palette))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    nameField
                    ThemePreviewCardView(palette: viewModel.palette, showsExtras: true)
                    colorCard
                    contrastCard
                    actionsCard
                }
                .padding(Theme.cardPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(viewModel.isNew ? AppStrings.Themes.newTheme : AppStrings.Themes.editTheme)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar") {
                        viewModel.save(to: store)
                        dismiss()
                    }
                    .disabled(!viewModel.canSave)
                }
            }
            .confirmationDialog(
                AppStrings.Themes.deleteConfirm(viewModel.draft.name),
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button(AppStrings.Themes.editorDelete, role: .destructive) {
                    store.deleteCustomTheme(id: viewModel.draft.id)
                    dismiss()
                }
                Button("Annuleren", role: .cancel) { }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Naam

    private var nameField: some View {
        HStack {
            Text(AppStrings.Themes.editorName)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            TextField(AppStrings.Themes.defaultCustomName, text: $viewModel.draft.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
                .submitLabel(.done)
        }
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
    }

    // MARK: - Kleuren

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.Themes.editorColors.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)

            fieldPicker

            ColorWheelView(color: Binding(
                get: { viewModel.selectedHSB },
                set: { viewModel.updateSelectedColor($0) }
            ))
            .frame(maxWidth: 240)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            slider(AppStrings.Themes.editorBrightness, value: \.brightness)
            slider(AppStrings.Themes.editorSaturation, value: \.saturation)

            hexField
        }
        .padding(Theme.cardPadding)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    /// Zes kleurvelden als compacte chips met staal.
    private var fieldPicker: some View {
        let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(CustomTheme.Field.allCases) { field in
                let isSelected = viewModel.selectedField == field
                Button {
                    isHexFocused = false
                    viewModel.select(field)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.draft[field].color)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                        Text(field.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? Theme.onAccent : Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        if viewModel.contrastIssues.contains(where: { $0.field == field }) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(isSelected ? Theme.onAccent : Theme.warning)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(isSelected ? Theme.accent : Theme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func slider(_ title: String, value keyPath: WritableKeyPath<HSBColor, Double>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 78, alignment: .leading)
            Slider(value: Binding(
                get: { viewModel.selectedHSB[keyPath: keyPath] },
                set: { newValue in
                    var hsb = viewModel.selectedHSB
                    hsb[keyPath: keyPath] = newValue
                    viewModel.updateSelectedColor(hsb)
                }
            ), in: 0...1)
            .tint(Theme.accent)
            Text("\(Int((viewModel.selectedHSB[keyPath: keyPath] * 100).rounded()))%")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private var hexField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(AppStrings.Themes.editorHex)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 78, alignment: .leading)
                TextField("#RRGGBB", text: $viewModel.hexInput)
                    .font(.body.monospaced())
                    .foregroundStyle(Theme.textPrimary)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($isHexFocused)
                    .submitLabel(.done)
                    .onSubmit { viewModel.applyHexInput() }
                    .onChange(of: viewModel.hexInput) { _, _ in
                        // Live toepassen zodra de invoer compleet en geldig is.
                        if isHexFocused { viewModel.applyHexInput() }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(viewModel.draft[viewModel.selectedField].color)
                    .frame(width: 32, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.border, lineWidth: 1))
            }
            if !viewModel.isHexInputValid {
                Text(AppStrings.Themes.editorInvalidHex)
                    .font(.caption2)
                    .foregroundStyle(Theme.warning)
                    .padding(.leading, 88)
            }
        }
    }

    // MARK: - Contrast

    private var contrastCard: some View {
        let issues = viewModel.contrastIssues
        return VStack(alignment: .leading, spacing: 8) {
            if issues.isEmpty {
                Label(AppStrings.Themes.editorContrastOK, systemImage: "checkmark.shield")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(issues) { issue in
                    Label(
                        AppStrings.Themes.editorContrastIssue(issue.field.displayName, ratio: issue.ratio, minimum: issue.minimum),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { viewModel.autoCorrectContrast() }
                } label: {
                    Label(AppStrings.Themes.editorAutoFix, systemImage: "wand.and.stars")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .foregroundStyle(Theme.onAccent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
    }

    // MARK: - Acties

    private var actionsCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    Button(AppStrings.Themes.editorGenerateDark) {
                        withAnimation(.easeInOut(duration: 0.3)) { viewModel.generateFromAccent(dark: true) }
                    }
                    Button(AppStrings.Themes.editorGenerateLight) {
                        withAnimation(.easeInOut(duration: 0.3)) { viewModel.generateFromAccent(dark: false) }
                    }
                } label: {
                    actionLabel(AppStrings.Themes.editorGenerate, systemImage: "sparkles")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { viewModel.resetColors() }
                } label: {
                    actionLabel(AppStrings.Themes.editorResetColors, systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
            }

            if !viewModel.isNew {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label(AppStrings.Themes.editorDelete, systemImage: "trash")
                        .font(.subheadline)
                        .foregroundStyle(Theme.loss)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
    }
}

#Preview {
    ThemeEditorView(theme: nil, store: ThemeStore(defaults: UserDefaults(suiteName: "preview")!))
}
