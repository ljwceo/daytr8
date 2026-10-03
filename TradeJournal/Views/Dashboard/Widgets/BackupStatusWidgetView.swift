import SwiftUI

/// Backup-status: wanneer de laatste backup was, of hij te oud is en hoe
/// de automatische backup staat. Tikken opent Backup & herstel.
struct BackupStatusWidgetView: View {

    let context: WidgetRenderContext

    @AppStorage(BackupSettings.Keys.lastBackupDate) private var lastBackupInterval: Double = 0
    @AppStorage(BackupSettings.Keys.autoBackupFrequency) private var autoBackupFrequencyRaw = AutoBackupFrequency.off.rawValue
    @AppStorage(BackupSettings.Keys.lastAutoBackupError) private var autoBackupError = ""

    private var lastBackup: Date? {
        lastBackupInterval > 0 ? Date(timeIntervalSince1970: lastBackupInterval) : nil
    }

    var body: some View {
        let stale = BackupSettings.isStale(lastBackup: lastBackup)
        let frequency = AutoBackupFrequency(rawValue: autoBackupFrequencyRaw) ?? .off

        NavigationLink {
            BackupView()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: stale ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                        .foregroundStyle(stale ? Theme.warning : Theme.profit)
                    Text(statusText(stale: stale))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                }
                Text(lastBackup.map { "Laatste: \($0.formatted(.relative(presentation: .named)))" } ?? "Nog nooit een backup gemaakt")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text("Automatisch: \(frequency.displayName)")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                if !autoBackupError.isEmpty {
                    Text("Automatische backup mislukt")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.loss)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
    }

    private func statusText(stale: Bool) -> String {
        if lastBackup == nil { return "Maak een backup" }
        return stale ? "Backup ouder dan 7 dagen" : "Backup is actueel"
    }
}

/// Status van de laatste backup.
struct BackupStatusWidgetDefinition: DashboardWidgetDefinition {
    let type = DashboardWidgetType.backupStatus
    let title = "Backup-status"
    let systemImage = "externaldrive.badge.checkmark"
    let summary = "Wanneer je laatste backup was en of de automatische backup werkt."
    let defaultSize = WidgetSize.small
    let options: WidgetSettingsOptions = []

    func makeContent(_ context: WidgetRenderContext) -> AnyView {
        AnyView(BackupStatusWidgetView(context: context))
    }
}
