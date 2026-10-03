import SwiftUI

/// Vrije notitie op het dashboard (bijv. je regels of focus van de week).
/// Tikken opent de editor.
struct NoteWidgetView: View {

    let context: WidgetRenderContext

    var body: some View {
        let text = context.settings.noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        Button {
            context.onEditSettings()
        } label: {
            Group {
                if text.isEmpty {
                    Text("Tik om een notitie te schrijven.")
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    Text(text)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .font(.subheadline)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
    }
}

/// Notitie met eigen tekst; het instellingenscherm is een teksteditor.
struct NoteWidgetDefinition: DashboardWidgetDefinition {
    let type = DashboardWidgetType.note
    let title = "Notitie"
    let systemImage = "note.text"
    let summary = "Vrije tekst op je dashboard, bijv. je focus of regels van de week."
    let defaultSize = WidgetSize.small
    let options: WidgetSettingsOptions = []

    func makeContent(_ context: WidgetRenderContext) -> AnyView {
        AnyView(NoteWidgetView(context: context))
    }

    func makeSettingsView(_ settings: Binding<WidgetSettings>, accounts: [Account]) -> AnyView {
        AnyView(
            Section("Notitie") {
                TextEditor(text: settings.noteText)
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Theme.textPrimary)
            }
            .listRowBackground(Theme.card)
        )
    }
}
