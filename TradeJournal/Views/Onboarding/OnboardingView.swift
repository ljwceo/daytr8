import SwiftUI

/// Swipebare rondleiding (7 stappen) met voortgangsbolletjes,
/// "Volgende" / "Overslaan" en op de laatste stap de keuze tussen
/// "Eerste trade toevoegen" en "Naar dashboard".
struct OnboardingView: View {

    @Environment(OnboardingViewModel.self) private var viewModel

    private let steps = OnboardingStep.allCases

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            topBar

            TabView(selection: $viewModel.currentStep) {
                ForEach(steps) { step in
                    OnboardingPageView(step: step)
                        .tag(step)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)

            progressDots
                .padding(.vertical, 12)

            bottomButtons
                .padding(.horizontal, Theme.cardPadding)
                .padding(.bottom, 12)
        }
        .background(Theme.background.ignoresSafeArea())
        // Eigen presentatie: volg het thema ook hier, zodat een wissel in
        // stap 4 meteen goed oogt (licht ↔ donker).
        .preferredColorScheme(Theme.colorScheme)
    }

    // MARK: - Onderdelen

    private var topBar: some View {
        HStack {
            Text(AppStrings.Onboarding.progress(step: viewModel.currentStep.rawValue + 1, of: steps.count))
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            if !viewModel.currentStep.isLast {
                Button(AppStrings.Onboarding.skip) {
                    viewModel.skipTour()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, Theme.cardPadding)
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(steps) { step in
                Capsule()
                    .fill(step == viewModel.currentStep ? Theme.accent : Theme.textTertiary.opacity(0.5))
                    .frame(width: step == viewModel.currentStep ? 22 : 8, height: 8)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.currentStep)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppStrings.Onboarding.progress(step: viewModel.currentStep.rawValue + 1, of: steps.count))
    }

    @ViewBuilder
    private var bottomButtons: some View {
        if viewModel.currentStep.isLast {
            VStack(spacing: 10) {
                Button {
                    viewModel.finish(.firstTrade)
                } label: {
                    Label(AppStrings.Onboarding.firstTrade, systemImage: "plus")
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())

                Button {
                    viewModel.finish(.dashboard)
                } label: {
                    Text(AppStrings.Onboarding.toDashboard)
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.goToNextStep()
                }
            } label: {
                Text(AppStrings.Onboarding.next)
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
        }
    }
}

// MARK: - Pagina

/// Eén stap: icoon, titel, 2–3 zinnen en stap-specifieke inhoud.
private struct OnboardingPageView: View {

    let step: OnboardingStep

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: step.systemImage)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 64, height: 64)
                    .background(Theme.accent.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .accessibilityHidden(true)

                Text(step.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)

                Text(step.message)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                content
                    .padding(.top, 4)
            }
            .padding(Theme.cardPadding)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            WelcomeHighlightsView()
        case .navigation:
            TabBarDemoView()
        case .confluences:
            ConfluenceDemoView()
        case .themes:
            ThemePickerView()
        case .addTrade:
            AddTradeStepsView()
        case .screenshotImport:
            VStack(alignment: .leading, spacing: 12) {
                ScreenshotExampleView()
                Label(AppStrings.Onboarding.importWhere, systemImage: "hand.tap")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        case .done:
            DoneBadgeView()
        }
    }
}

// MARK: - Stap 1: welkom

private struct WelcomeHighlightsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(AppStrings.Onboarding.welcomeHighlights, id: \.self) { item in
                Label {
                    Text(item)
                        .foregroundStyle(Theme.textPrimary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.profit)
                }
                .font(.subheadline)
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

// MARK: - Stap 2: navigatie

/// Nagebootste tabbalk met dezelfde tabs als `RootTabView` (`AppTab`).
/// De gekozen tab is gemarkeerd; eronder staat wat je er vindt.
private struct TabBarDemoView: View {

    @State private var selected: AppTab = .dashboard

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selected.systemImage)
                    .foregroundStyle(Theme.accent)
                    .font(.title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(selected.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(selected.onboardingDescription)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .id(selected)
            .transition(.opacity)

            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    let isSelected = tab == selected
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { selected = tab }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.systemImage)
                                .font(.body)
                            Text(tab.title)
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                                .fill(isSelected ? Theme.accent.opacity(0.15) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(6)
            .background(Theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Theme.accent.opacity(0.6), lineWidth: 1.5)
            )
        }
    }
}

// MARK: - Stap 3: confluences

/// Aanvinkbare voorbeeld-confluences met een sterktemeter.
private struct ConfluenceDemoView: View {

    @State private var selected: Set<String> = [AppStrings.Onboarding.confluencesExamples[0]]

    private var examples: [String] { AppStrings.Onboarding.confluencesExamples }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                FlowLayout(spacing: 8) {
                    ForEach(examples, id: \.self) { name in
                        ChipView(
                            title: name,
                            systemImage: selected.contains(name) ? "checkmark" : "plus",
                            color: Theme.accent,
                            selectedForeground: Theme.onAccent,
                            isSelected: selected.contains(name)
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if selected.contains(name) {
                                    selected.remove(name)
                                } else {
                                    selected.insert(name)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(AppStrings.Onboarding.confluencesStrength)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 6) {
                        ForEach(0..<examples.count, id: \.self) { index in
                            Capsule()
                                .fill(index < selected.count ? strengthColor : Theme.elevated)
                                .frame(height: 8)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(AppStrings.Onboarding.confluencesStrength): \(selected.count) van \(examples.count)")
                }
            }
            .padding(Theme.cardPadding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

            Label(AppStrings.Onboarding.confluencesWhere, systemImage: "hand.tap")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var strengthColor: Color {
        selected.count == examples.count ? Theme.profit : Theme.accent
    }
}

// MARK: - Stap 5: trade toevoegen

/// Genummerde stappen van het tradeformulier; tik voor uitleg.
private struct AddTradeStepsView: View {

    @State private var expanded: Int? = 0

    private var steps: [(title: String, detail: String)] { AppStrings.Onboarding.addTradeSteps }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(steps.indices, id: \.self) { index in
                let isExpanded = expanded == index
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        expanded = isExpanded ? nil : index
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(isExpanded ? Theme.onAccent : Theme.accent)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(isExpanded ? Theme.accent : Theme.accent.opacity(0.15)))
                            Text(steps[index].title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textTertiary)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                        if isExpanded {
                            Text(steps[index].detail)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.leading, 36)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, Theme.cardPadding)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < steps.count - 1 {
                    Divider()
                        .overlay(Theme.separator)
                        .padding(.leading, Theme.cardPadding + 36)
                }
            }
        }
        .padding(.vertical, 4)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

// MARK: - Stap 7: klaar

private struct DoneBadgeView: View {
    var body: some View {
        HStack {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                .font(.system(size: 88))
                .foregroundStyle(Theme.profit)
                .padding(.vertical, 24)
                .accessibilityHidden(true)
            Spacer()
        }
    }
}

// MARK: - Knopstijlen

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

#Preview {
    OnboardingView()
        .environment(OnboardingViewModel(settings: OnboardingSettings(defaults: UserDefaults(suiteName: "preview")!)))
}
