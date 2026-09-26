import Foundation

/// De stappen van de onboarding-carousel, in volgorde.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case navigation
    case confluences
    case themes
    case addTrade
    case screenshotImport
    case done

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return AppStrings.Onboarding.welcomeTitle
        case .navigation: return AppStrings.Onboarding.navigationTitle
        case .confluences: return AppStrings.Onboarding.confluencesTitle
        case .themes: return AppStrings.Onboarding.themesTitle
        case .addTrade: return AppStrings.Onboarding.addTradeTitle
        case .screenshotImport: return AppStrings.Onboarding.importTitle
        case .done: return AppStrings.Onboarding.doneTitle
        }
    }

    var message: String {
        switch self {
        case .welcome: return AppStrings.Onboarding.welcomeBody
        case .navigation: return AppStrings.Onboarding.navigationBody
        case .confluences: return AppStrings.Onboarding.confluencesBody
        case .themes: return AppStrings.Onboarding.themesBody
        case .addTrade: return AppStrings.Onboarding.addTradeBody
        case .screenshotImport: return AppStrings.Onboarding.importBody
        case .done: return AppStrings.Onboarding.doneBody
        }
    }

    var systemImage: String {
        switch self {
        case .welcome: return "hand.wave"
        case .navigation: return "square.grid.3x1.below.line.grid.1x2"
        case .confluences: return "checklist"
        case .themes: return "paintpalette"
        case .addTrade: return "plus.circle"
        case .screenshotImport: return "text.viewfinder"
        case .done: return "checkmark.seal"
        }
    }

    var isLast: Bool { self == OnboardingStep.allCases.last }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
}
