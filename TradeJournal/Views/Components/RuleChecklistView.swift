import SwiftUI

/// Checklist van de dagelijkse regels voor één dag. Automatische regels tonen
/// hun beoordeling; handmatige regels zijn aan te tikken (`onToggle`).
/// Gebruikt door `ProgressTrackerView` en `DayDetailView`.
struct RuleChecklistView: View {

    let progress: DayProgress
    let onToggle: (UUID) -> Void

    var body: some View {
        if progress.evaluations.isEmpty {
            Text("Geen actieve regels voor deze dag. Voeg regels toe in de progress tracker.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(progress.evaluations) { evaluation in
                    row(evaluation)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ evaluation: RuleEvaluation) -> some View {
        let content = HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName(for: evaluation))
                .font(.title3)
                .foregroundStyle(evaluation.isFollowed ? Theme.profit : (evaluation.kind.isAutomatic ? Theme.loss : Theme.textTertiary))
            VStack(alignment: .leading, spacing: 2) {
                Text(evaluation.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(evaluation.kind.isAutomatic ? "\(evaluation.detail) · automatisch" : evaluation.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())

        if evaluation.kind.isAutomatic {
            content
        } else {
            Button {
                onToggle(evaluation.ruleID)
            } label: {
                content
            }
            .buttonStyle(.plain)
        }
    }

    private func iconName(for evaluation: RuleEvaluation) -> String {
        if evaluation.isFollowed { return "checkmark.circle.fill" }
        return evaluation.kind.isAutomatic ? "xmark.circle.fill" : "circle"
    }
}
