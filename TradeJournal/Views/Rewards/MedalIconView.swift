import SwiftUI

/// Rond medaille-icoon in de kleuren van het materiaal (`MedalTier`), met
/// het icoon van de categorie. Vergrendeld: grijs en half doorzichtig.
struct MedalIconView: View {

    let definition: MedalDefinition
    var isUnlocked: Bool = true
    var size: CGFloat = 56

    var body: some View {
        let tier = definition.tier
        ZStack {
            Circle()
                .fill(LinearGradient(colors: Theme.medalGradient(tier), startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .strokeBorder(
                    LinearGradient(colors: Theme.medalGradient(tier).reversed(), startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: size * 0.08
                )
            Image(systemName: symbolName)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(Theme.onMedal(tier))
        }
        .frame(width: size, height: size)
        .saturation(isUnlocked ? 1 : 0)
        .opacity(isUnlocked ? 1 : 0.4)
        .shadow(color: isUnlocked ? Theme.medalGlow(tier) : .clear, radius: size * 0.18)
        .overlay(alignment: .bottomTrailing) {
            if !isUnlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.2, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(size * 0.06)
                    .background(Circle().fill(Theme.elevated))
            }
        }
        .accessibilityHidden(true)
    }

    /// Verborgen medailles tonen tot het behalen een vraagteken.
    private var symbolName: String {
        definition.isHidden && !isUnlocked ? "questionmark" : definition.systemImage
    }
}

#Preview {
    HStack {
        ForEach(MedalTier.allCases) { tier in
            MedalIconView(definition: MedalCatalog.all.first { $0.tier == tier }!, size: 30)
        }
    }
    .padding()
    .background(Theme.background)
}
