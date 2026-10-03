import SwiftUI

/// Kaart rond een widget: kop met titel (en eventueel de periode) en, in de
/// bewerkmodus, knoppen om te verplaatsen, van grootte te wisselen, in te
/// stellen of te verwijderen.
struct WidgetContainerView: View {

    let title: String
    let systemImage: String
    var subtitle: String? = nil
    let content: AnyView
    var isEditing = false
    var canToggleSize = true
    var size: WidgetSize = .large
    var onToggleSize: () -> Void = {}
    var onSettings: () -> Void = {}
    var onDelete: () -> Void = {}
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isEditing {
                editBar
            }
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            content
                .allowsHitTesting(!isEditing)
                .opacity(isEditing ? 0.75 : 1)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.accent.opacity(isEditing ? 0.6 : 0), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
    }

    private var editBar: some View {
        HStack(spacing: 14) {
            // Slepen werkt op de hele kaart; dit menu is het alternatief zonder slepen.
            Menu {
                Button(action: onMoveUp) { Label("Omhoog", systemImage: "arrow.up") }
                Button(action: onMoveDown) { Label("Omlaag", systemImage: "arrow.down") }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(Theme.textTertiary)
            }
            .accessibilityLabel("Verplaatsen")
            Spacer(minLength: 0)
            if canToggleSize {
                Button(action: onToggleSize) {
                    Image(systemName: size == .large ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel(size == .large ? "Maak klein" : "Maak groot")
            }
            Button(action: onSettings) {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("Instellingen")
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill").foregroundStyle(Theme.loss)
            }
            .accessibilityLabel("Verwijderen")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.accent)
        .buttonStyle(.plain)
    }
}

/// Bibliotheek met alle widgettypes en een voorbeeldweergave per widget
/// (met je eigen data). Tikken op "Toevoegen" zet de widget onderaan het
/// dashboard.
struct WidgetLibraryView: View {

    let previewContext: (any DashboardWidgetDefinition) -> WidgetRenderContext
    let onAdd: (any DashboardWidgetDefinition) -> Void

    @Environment(\.dismiss) private var dismiss

    private var types: [DashboardWidgetType] {
        DashboardWidgetRegistry.definitions.map { $0.type }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.widgetSpacing) {
                    ForEach(types) { type in
                        if let definition = DashboardWidgetRegistry.definition(for: type) {
                            item(definition)
                        }
                    }
                }
                .padding(Theme.cardPadding)
            }
            .background(Theme.background)
            .navigationTitle("Widget toevoegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluiten") { dismiss() }
                }
            }
        }
    }

    private func item(_ definition: any DashboardWidgetDefinition) -> some View {
        let context = previewContext(definition)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: definition.systemImage)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(definition.title)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(definition.summary)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button {
                    onAdd(definition)
                    dismiss()
                } label: {
                    Text("Toevoegen")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(Theme.onAccent)
                        .background(Theme.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // Voorbeeld: de echte widget met je eigen data, niet interactief.
            WidgetContainerView(
                title: definition.displayTitle(for: context.settings),
                systemImage: definition.systemImage,
                content: definition.makeContent(context)
            )
            .frame(maxWidth: definition.defaultSize == .small ? Theme.widgetSmallPreviewWidth : .infinity, alignment: .leading)
            .background(Theme.background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .padding(Theme.cardPadding)
        .background(Theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}
