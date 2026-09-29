import SwiftUI
import UIKit

/// Importlogboek: elke stap van het kiezen en inlezen van een backup, om te
/// kopiëren of te delen als herstellen op het toestel niet lukt.
struct ImportLogView: View {

    let log: ImportDiagnosticsLog

    @State private var didCopy = false
    @State private var isConfirmingClear = false

    var body: some View {
        List {
            Section {
                Text(ImportDiagnosticsLog.appVersionDescription + " · iOS " + ImportDiagnosticsLog.systemVersion)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                if didCopy {
                    Label("Gekopieerd naar het klembord.", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.profit)
                }
            }
            .listRowBackground(Theme.card)

            Section {
                if log.entries.isEmpty {
                    Text("Nog niets gelogd. Probeer een backup te herstellen en kom hier terug.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    // Nieuwste bovenaan.
                    ForEach(log.entries.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.step)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(entry.date.formatted(date: .omitted, time: .standard))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            if let detail = entry.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Theme.textSecondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            } header: {
                Text("Stappen (\(log.entries.count))")
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Importlogboek")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = log.exportText()
                        didCopy = true
                    } label: {
                        Label("Kopieer", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: log.exportText(), subject: Text("Daytr8 importlogboek")) {
                        Label("Deel", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        isConfirmingClear = true
                    } label: {
                        Label("Wis logboek", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Importlogboek wissen?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Wis logboek", role: .destructive) {
                log.clear()
                didCopy = false
            }
            Button("Annuleren", role: .cancel) {}
        }
    }
}

#Preview {
    NavigationStack {
        ImportLogView(log: ImportDiagnosticsLog(fileURL: nil))
    }
    .preferredColorScheme(.dark)
}
