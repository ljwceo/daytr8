import SwiftUI

/// Overzicht van de meegeleverde broker-templates voor "Vul in vanuit
/// screenshot" (SPEC.md §12). Alleen-lezen: eigen templates aanmaken en
/// bewerken is een latere fase.
struct ScreenshotTemplatesView: View {

    private let templates = ScreenshotTemplateStore.bundled

    var body: some View {
        List {
            Section {
                ForEach(templates) { template in
                    NavigationLink {
                        ScreenshotTemplateDetailView(template: template)
                    } label: {
                        templateRow(template)
                    }
                }
            } footer: {
                Text("Het platform wordt herkend aan de sleutelwoorden op de screenshot. Wordt niets herkend, dan vult het generieke template aan wat het kan vinden.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Screenshot-templates")
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .overlay {
            if templates.isEmpty {
                ContentUnavailableView("Geen templates gevonden", systemImage: "doc.text.magnifyingglass")
            }
        }
    }

    private func templateRow(_ template: ScreenshotTemplate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(template.name)
                    .foregroundStyle(Theme.textPrimary)
                if template.isFallbackTemplate {
                    Text("Terugval")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text("\(template.definedFields.count) velden")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Details van één template: sleutelwoorden, velden en hun regexen.
private struct ScreenshotTemplateDetailView: View {

    let template: ScreenshotTemplate

    var body: some View {
        List {
            Section("Sleutelwoorden") {
                if template.keywords.isEmpty {
                    Text("Geen — wordt gebruikt als geen platform herkend is.")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(template.keywords, id: \.self) { keyword in
                            ChipView(title: keyword, isSelected: false)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Velden") {
                ForEach(template.definedFields) { field in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(field.displayName)
                            .foregroundStyle(Theme.textPrimary)
                        ForEach(template.rule(for: field)?.patterns ?? [], id: \.self) { pattern in
                            Text(pattern)
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                LabeledContent("Id", value: template.id)
                LabeledContent("Formaatversie", value: "\(template.formatVersion)")
                if let order = template.dateOrder {
                    LabeledContent("Datumnotatie", value: order.displayName)
                }
            } footer: {
                Text("Templates zijn JSON-bestanden in Resources/ScreenshotTemplates. Een nieuw platform toevoegen kan zonder code aan te passen.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
