import SwiftUI

/// Waarschuwing als de laatste backup ouder is dan 7 dagen (SPEC §9).
///
/// Leest de datum rechtstreeks via `@AppStorage`, zodat de banner direct
/// verdwijnt zodra er ergens in de app een backup gemaakt is. Tikken opent
/// `BackupView`; de banner moet dus binnen een `NavigationStack` staan.
struct BackupReminderBannerView: View {

    @AppStorage(BackupSettings.Keys.lastBackupDate) private var lastBackupInterval: Double = 0

    private var lastBackup: Date? {
        lastBackupInterval > 0 ? Date(timeIntervalSince1970: lastBackupInterval) : nil
    }

    var isVisible: Bool {
        BackupSettings.isStale(lastBackup: lastBackup)
    }

    var body: some View {
        if isVisible {
            NavigationLink {
                BackupView()
            } label: {
                content
            }
            .buttonStyle(.plain)
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(lastBackup == nil ? "Nog geen backup gemaakt" : "Laatste backup is ouder dan 7 dagen")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detailText)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(Theme.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Theme.warning.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.warning.opacity(0.4), lineWidth: 1)
        )
    }

    private var detailText: String {
        var text = "Bij opnieuw signen of een ingetrokken certificaat kan lokale data verloren gaan."
        if let lastBackup {
            text += " Laatste backup: \(lastBackup.formatted(date: .abbreviated, time: .shortened))."
        }
        return text + " Tik om nu een backup te maken."
    }
}
