import SwiftUI

/// Medaille-overzicht: behaalde medailles (met datum), vergrendelde
/// (grijs, met voortgang) en verborgen medailles, per categorie.
/// Te openen via de medaille-knop op het dashboard, een medaillemelding of
/// Meer → Medailles.
struct MedalsView: View {

    @Environment(RewardsViewModel.self) private var rewards
    @Environment(\.dismiss) private var dismiss

    /// In een sheet: met Sluiten-knop.
    var showsCloseButton = false

    private enum Filter: String, CaseIterable, Identifiable {
        case all, unlocked, locked
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "Alle"
            case .unlocked: return "Behaald"
            case .locked: return "Te behalen"
            }
        }
    }

    @State private var filter: Filter = .all
    @State private var selected: MedalDefinition?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard

                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    ForEach(MedalCategory.allCases) { category in
                        let medals = visibleMedals(in: category)
                        if !medals.isEmpty {
                            categorySection(category, medals: medals)
                        }
                    }
                }
                .padding(Theme.cardPadding)
            }
            .onAppear {
                guard let id = rewards.highlightedMedalID else { return }
                DispatchQueue.main.async {
                    withAnimation { scroller.scrollTo(id, anchor: .center) }
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(AppStrings.Rewards.medalsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sluiten") { dismiss() }
                }
            }
        }
        .sheet(item: $selected) { definition in
            MedalDetailView(definition: definition)
                .presentationDetents([.medium])
                .presentationBackground(Theme.background)
        }
    }

    // MARK: - Samenvatting

    private var summaryCard: some View {
        let unlocked = rewards.unlockedCount
        let total = rewards.totalCount
        let highest = MedalCatalog.all
            .filter { rewards.store.isUnlocked($0.id) }
            .max { $0.tier < $1.tier }

        return HStack(spacing: 14) {
            if let highest {
                MedalIconView(definition: highest, size: 52)
            } else {
                Image(systemName: "rosette")
                    .font(.title)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 52, height: 52)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(AppStrings.Rewards.unlockedSummary(unlocked, of: total))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                ProgressView(value: Double(unlocked), total: Double(max(total, 1)))
                    .tint(Theme.accent)
                if let next = nextMedal {
                    Text("Volgende: \(next.name) · \(MedalService.progressText(of: next, in: rewards.evaluation))")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    /// De niet-verborgen, nog niet behaalde medaille die het dichtst bij is.
    private var nextMedal: MedalDefinition? {
        MedalCatalog.all
            .filter { !$0.isHidden && !rewards.store.isUnlocked($0.id) }
            .max { MedalService.progress(of: $0, in: rewards.evaluation) < MedalService.progress(of: $1, in: rewards.evaluation) }
    }

    // MARK: - Categorieën

    private func visibleMedals(in category: MedalCategory) -> [MedalDefinition] {
        MedalCatalog.definitions(in: category).filter { definition in
            switch filter {
            case .all: return true
            case .unlocked: return rewards.store.isUnlocked(definition.id)
            case .locked: return !rewards.store.isUnlocked(definition.id)
            }
        }
    }

    private func categorySection(_ category: MedalCategory, medals: [MedalDefinition]) -> some View {
        let unlockedInCategory = MedalCatalog.definitions(in: category).filter { rewards.store.isUnlocked($0.id) }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(category.title, systemImage: category.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(unlockedInCategory)/\(MedalCatalog.definitions(in: category).count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(medals) { definition in
                    tile(definition)
                        .id(definition.id)
                }
            }
        }
    }

    private func tile(_ definition: MedalDefinition) -> some View {
        let unlockedAt = rewards.store.unlocked[definition.id]
        let isUnlocked = unlockedAt != nil
        let isHighlighted = rewards.highlightedMedalID == definition.id
        let concealed = definition.isHidden && !isUnlocked

        return Button {
            selected = definition
        } label: {
            VStack(spacing: 6) {
                MedalIconView(definition: definition, isUnlocked: isUnlocked, size: 48)
                Text(concealed ? AppStrings.Rewards.hiddenName : definition.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isUnlocked ? Theme.textPrimary : Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let unlockedAt {
                    Text(unlockedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                } else if !concealed {
                    ProgressView(value: MedalService.progress(of: definition, in: rewards.evaluation))
                        .tint(Theme.accent)
                        .scaleEffect(y: 0.8)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .top)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                    .stroke(isHighlighted ? Theme.accent : Theme.border, lineWidth: isHighlighted ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(concealed ? AppStrings.Rewards.hiddenName : definition.name)
        .accessibilityValue(isUnlocked ? AppStrings.Rewards.unlocked : MedalService.progressText(of: definition, in: rewards.evaluation))
    }
}

/// Details van één medaille: beschrijving, voortgang en datum van behalen.
struct MedalDetailView: View {

    @Environment(RewardsViewModel.self) private var rewards

    let definition: MedalDefinition

    var body: some View {
        let unlockedAt = rewards.store.unlocked[definition.id]
        let concealed = definition.isHidden && unlockedAt == nil

        VStack(spacing: 14) {
            MedalIconView(definition: definition, isUnlocked: unlockedAt != nil, size: 88)
                .padding(.top, 24)

            Text(concealed ? AppStrings.Rewards.hiddenName : definition.name)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)

            Text("\(definition.tier.displayName) · \(definition.category.title)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            Text(concealed ? AppStrings.Rewards.hiddenDetail : definition.detail)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.cardPadding)

            if let unlockedAt {
                Label("Behaald op \(unlockedAt.formatted(date: .long, time: .omitted))", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.profit)
            } else if !concealed {
                VStack(spacing: 6) {
                    ProgressView(value: MedalService.progress(of: definition, in: rewards.evaluation))
                        .tint(Theme.accent)
                    Text(MedalService.progressText(of: definition, in: rewards.evaluation))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 40)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        MedalsView()
    }
    .environment(RewardsViewModel(store: MedalStore(defaults: UserDefaults(suiteName: "preview")!)))
}
