import Foundation
import SwiftUI
import SwiftData
import UIKit

/// Volledig detailscherm van één trade: alle velden, confluences als chips,
/// playbook-checklist (wat wel/niet gevolgd), tags/fouten en screenshots
/// (fullscreen met pinch-to-zoom via `ScreenshotViewerView`).
struct TradeDetailView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let trade: Trade

    private let statsService = StatsService()
    private let editingService = TradeEditingService()

    @State private var showingEdit = false
    @State private var confirmDelete = false
    @State private var showingViewer = false
    @State private var viewerStartIndex = 0

    private var metrics: TradeMetrics { statsService.metrics(for: trade) }
    private var currency: String { trade.account?.currency ?? "USD" }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    priceCard
                    if !trade.confluences.isEmpty { confluencesCard }
                    if let playbook = trade.playbook, !playbook.rules.isEmpty { playbookCard(playbook) }
                    if !trade.tags.isEmpty || !trade.mistakes.isEmpty { tagsAndMistakesCard }
                    if hasReflectionContent { reflectionCard }
                    if !trade.screenshots.isEmpty { screenshotsCard }
                }
                .padding(16)
            }
        }
        .navigationTitle(trade.symbol)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingEdit = true
                    } label: {
                        Label("Bewerken", systemImage: "pencil")
                    }
                    Button {
                        editingService.duplicate(trade, in: modelContext)
                    } label: {
                        Label("Dupliceren", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Verwijderen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            TradeFormView(mode: .edit(trade))
        }
        .fullScreenCover(isPresented: $showingViewer) {
            ScreenshotViewerView(
                screenshots: trade.screenshots.sorted { $0.sortOrder < $1.sortOrder },
                startIndex: viewerStartIndex
            )
        }
        .confirmationDialog(
            "Trade verwijderen?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Verwijderen", role: .destructive) {
                editingService.delete(trade, from: modelContext)
                dismiss()
            }
            Button("Annuleren", role: .cancel) { }
        }
    }

    // MARK: - Kaarten

    private var headerCard: some View {
        card(title: "Resultaat") {
            HStack {
                metricColumn(
                    title: metrics.outcome == .open ? "Status" : "Netto P&L",
                    value: metrics.outcome == .open ? "Open" : metrics.netPnL.formatted(.currency(code: currency)),
                    color: Theme.color(forPnL: metrics.netPnL)
                )
                metricColumn(
                    title: "R-multiple",
                    value: metrics.rMultiple.map { String(format: "%.2fR", $0) } ?? "—",
                    color: Theme.textPrimary
                )
                metricColumn(title: "Sessie", value: trade.session.displayName, color: Theme.textPrimary)
            }

            Divider().background(Theme.separator)

            infoRow("Account", trade.account?.name ?? "—")
            infoRow("Richting", trade.direction.displayName)
            infoRow("Playbook", trade.playbook?.name ?? "—")
            infoRow("Entry", trade.entryDate.formatted(date: .abbreviated, time: .shortened))
            if let exitDate = trade.exitDate {
                infoRow("Exit", exitDate.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private var priceCard: some View {
        card(title: "Prijzen & risk") {
            infoRow("Entry-prijs", String(format: "%.5g", trade.entryPrice))
            if let exit = trade.exitPrice {
                infoRow("Exit-prijs", String(format: "%.5g", exit))
            }
            infoRow("Aantal", String(format: "%.4g", trade.quantity))
            if let stop = trade.stopLoss {
                infoRow("Stop loss", String(format: "%.5g", stop))
            }
            if let target = trade.takeProfit {
                infoRow("Take profit", String(format: "%.5g", target))
            }
            if let risk = metrics.riskAmount {
                infoRow("Geplande risk", risk.formatted(.currency(code: currency)))
            }
            if let mae = trade.mae {
                infoRow("MAE", String(format: "%.5g", mae))
            }
            if let mfe = trade.mfe {
                infoRow("MFE", String(format: "%.5g", mfe))
            }
            infoRow("Commissie", trade.commission.formatted(.currency(code: currency)))
            infoRow("Fees", trade.fees.formatted(.currency(code: currency)))
        }
    }

    private var confluencesCard: some View {
        card(title: "Confluences") {
            FlowLayout(spacing: 8) {
                ForEach(trade.confluences.sorted { $0.sortOrder < $1.sortOrder }) { confluence in
                    ChipView(
                        title: confluence.name,
                        systemImage: confluence.iconName,
                        color: Color(hex: confluence.colorHex),
                        isSelected: true
                    )
                }
            }
        }
    }

    private func playbookCard(_ playbook: Playbook) -> some View {
        card(title: "Playbook — \(playbook.name)") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(playbook.rules.sorted { $0.sortOrder < $1.sortOrder }) { rule in
                    let followed = trade.ruleAdherence.first { $0.rule?.id == rule.id }?.followed ?? false
                    HStack(spacing: 8) {
                        Image(systemName: followed ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(followed ? Theme.profit : Theme.textTertiary)
                        Text(rule.text)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
        }
    }

    private var tagsAndMistakesCard: some View {
        card(title: "Tags & fouten") {
            if !trade.tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(trade.tags) { tag in
                        ChipView(title: tag.name, color: Color(hex: tag.colorHex), isSelected: true)
                    }
                }
            }
            if !trade.mistakes.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(trade.mistakes) { mistake in
                        ChipView(title: mistake.name, systemImage: "exclamationmark.triangle", color: Color(hex: mistake.colorHex), isSelected: true)
                    }
                }
            }
        }
    }

    private var hasReflectionContent: Bool {
        !trade.notes.isEmpty || !trade.emotionBefore.isEmpty || !trade.emotionAfter.isEmpty || trade.rating > 0
    }

    private var reflectionCard: some View {
        card(title: "Reflectie") {
            if !trade.emotionBefore.isEmpty { infoRow("Emotie vóór", trade.emotionBefore) }
            if !trade.emotionAfter.isEmpty { infoRow("Emotie na", trade.emotionAfter) }
            if trade.rating > 0 {
                HStack {
                    Text("Rating").foregroundStyle(Theme.textSecondary)
                    Spacer()
                    StarRatingView(rating: .constant(trade.rating))
                }
            }
            if !trade.notes.isEmpty {
                Text(trade.notes)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }

    private var screenshotsCard: some View {
        let sorted = trade.screenshots.sorted { $0.sortOrder < $1.sortOrder }
        return card(title: "Screenshots") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, screenshot in
                        if let uiImage = UIImage(data: screenshot.imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewerStartIndex = index
                                    showingViewer = true
                                }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            content()
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private func metricColumn(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
        }
    }
}
