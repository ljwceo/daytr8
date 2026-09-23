import SwiftUI

/// Waarschuwing als de laatste backup ouder is dan 7 dagen (SPEC §9).
///
/// Leest de datum rechtstreeks via `@AppStorage`, zodat de banner direct
/// verdwijnt zodra er ergens in de app een backup gemaakt is. Tikken opent
/// `BackupView`; de banner moet dus binnen een `NavigationStack` staan.
/// Het kruisje zet de herinnering (na bevestiging) uit; weer aan te zetten
/// in Backup & herstel.
struct BackupReminderBannerView: View {

    @AppStorage(BackupSettings.Keys.lastBackupDate) private var lastBackupInterval: Double = 0
    @AppStorage(BackupSettings.Keys.reminderDismissed) private var isDismissed = false
    @AppStorage(BackupSettings.Keys.lastAutoBackupError) private var autoBackupError = ""

    @State private var confirmDismiss = false

    private var lastBackup: Date? {
        lastBackupInterval > 0 ? Date(timeIntervalSince1970: lastBackupInterval) : nil
    }

    var isVisible: Bool {
        BackupSettings.shouldShowReminder(lastBackup: lastBackup, dismissed: isDismissed)
    }

    var body: some View {
        if isVisible {
            HStack(alignment: .top, spacing: 8) {
                NavigationLink {
                    BackupView()
                } label: {
                    content
                }
                .buttonStyle(.plain)

                Button {
                    confirmDismiss = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Backupherinnering uitzetten")
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
            .alert("Backupherinnering uitzetten?", isPresented: $confirmDismiss) {
                Button("Ik begrijp het, uitzetten", role: .destructive) {
                    isDismissed = true
                }
                Button("Annuleren", role: .cancel) { }
            } message: {
                Text("Backups zijn belangrijk: zonder backup kan al je data verloren gaan, bijvoorbeeld bij opnieuw signen, een ingetrokken certificaat of het verwijderen van de app. Je krijgt geen herinnering meer. Je kunt hem weer aanzetten in Meer → Backup & herstel.")
            }
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
        }
        .contentShape(Rectangle())
    }

    private var detailText: String {
        if !autoBackupError.isEmpty {
            return "Automatische backup mislukt: \(autoBackupError) Tik om de backupmap te controleren."
        }
        var text = "Bij opnieuw signen of een ingetrokken certificaat kan lokale data verloren gaan."
        if let lastBackup {
            text += " Laatste backup: \(lastBackup.formatted(date: .abbreviated, time: .shortened))."
        }
        return text + " Tik om nu een backup te maken."
    }
}
