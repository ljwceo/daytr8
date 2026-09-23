import SwiftUI
import SwiftData

/// Beheer van de dagelijkse regels van de progress tracker: toevoegen,
/// bewerken, (de)activeren, sorteren en verwijderen.
struct DailyRulesView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DailyRule.sortOrder) private var rules: [DailyRule]

    @State private var viewModel = ProgressTrackerViewModel()
    @State private var editorTarget: EditorTarget?

    /// Welke regel de editor-sheet bewerkt (`nil`-regel = nieuw).
    private struct EditorTarget: Identifiable {
        let id = UUID()
        let rule: DailyRule?
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    ForEach(rules) { rule in
                        Button {
                            editorTarget = EditorTarget(rule: rule)
                        } label: {
                            row(rule)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { viewModel.deleteRule(rules[index], in: modelContext) }
                    }
                    .onMove { source, destination in
                        viewModel.moveRules(rules, from: source, to: destination)
                    }
                } footer: {
                    Text("Automatische regels worden beoordeeld op je trades en journal van die dag; handmatige regels vink je zelf af. Een nieuwe regel telt pas mee vanaf de dag dat je hem aanmaakt.")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Dagelijkse regels")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorTarget = EditorTarget(rule: nil)
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(item: $editorTarget) { target in
            DailyRuleEditorView(rule: target.rule, allRules: rules, viewModel: viewModel)
        }
    }

    private func row(_ rule: DailyRule) -> some View {
        HStack {
            Image(systemName: rule.kind.isAutomatic ? "bolt.circle" : "checkmark.circle")
                .foregroundStyle(rule.isActive ? Theme.accent : Theme.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(rule.isActive ? Theme.textPrimary : Theme.textTertiary)
                Text(subtitle(rule))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }

    private func subtitle(_ rule: DailyRule) -> String {
        var text = rule.kind.displayName
        if rule.kind.usesThreshold {
            text += rule.kind == .maxDailyLoss ? ": \(Theme.compactCurrency(rule.threshold))" : ": \(Int(rule.threshold))"
        }
        if !rule.isActive { text += " · inactief" }
        return text
    }
}

/// Sheet om één regel aan te maken of te bewerken.
private struct DailyRuleEditorView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let rule: DailyRule?
    let allRules: [DailyRule]
    let viewModel: ProgressTrackerViewModel

    @State private var draft: ProgressTrackerViewModel.RuleDraft

    init(rule: DailyRule?, allRules: [DailyRule], viewModel: ProgressTrackerViewModel) {
        self.rule = rule
        self.allRules = allRules
        self.viewModel = viewModel
        _draft = State(initialValue: rule.map(ProgressTrackerViewModel.RuleDraft.init(from:)) ?? ProgressTrackerViewModel.RuleDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Regel") {
                    TextField("Naam (bijv. Max 3 trades)", text: $draft.name)
                    Picker("Soort", selection: $draft.kind) {
                        ForEach(DailyRuleKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    if draft.kind.usesThreshold {
                        HStack {
                            Text(thresholdLabel)
                            Spacer()
                            DecimalFieldView(title: "Grens", value: $draft.threshold)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    Toggle("Actief", isOn: $draft.isActive)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(rule == nil ? "Nieuwe regel" : "Regel bewerken")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Opslaan") {
                        viewModel.saveRule(draft, existing: rule, allRules: allRules, in: modelContext)
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
            .onChange(of: draft.kind) { oldKind, newKind in
                // Zinvolle grens voorstellen bij het wisselen van soort.
                if newKind.usesThreshold, oldKind != newKind {
                    draft.threshold = newKind.defaultThreshold
                }
            }
        }
    }

    private var thresholdLabel: String {
        switch draft.kind {
        case .maxTrades: return "Max trades per dag"
        case .stopAfterLosses: return "Stop na aantal verliezen"
        case .maxDailyLoss: return "Max verlies ($)"
        case .manual, .journalFilled: return "Grens"
        }
    }
}
