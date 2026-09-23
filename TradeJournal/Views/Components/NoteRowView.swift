import SwiftUI

/// Rij voor een notebook-notitie: titel, eerste regels, koppelingen.
struct NoteRowView: View {

    let note: NotebookNote

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
                Text(note.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            if !preview.isEmpty {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            if note.linkedDate != nil || !note.trades.isEmpty {
                HStack(spacing: 10) {
                    if let date = note.linkedDate {
                        Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    }
                    if !note.trades.isEmpty {
                        Label("\(note.trades.count) trade(s)", systemImage: "list.bullet.rectangle")
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 4)
    }

    /// Inhoud zonder de regel die al als titel getoond wordt.
    private var preview: String {
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return body }
        return body.split(separator: "\n", omittingEmptySubsequences: true).dropFirst().joined(separator: " ")
    }
}
