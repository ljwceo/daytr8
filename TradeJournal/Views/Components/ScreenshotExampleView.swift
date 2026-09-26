import SwiftUI

/// Voorbeeld van een geschikte screenshot voor de screenshot-import: een
/// fictief tradeplatform (geen echte broker) met de velden die de app
/// herkent gemarkeerd en gelabeld ("dit wordt Entry"), plus een checklist.
///
/// Gebruikt in de onboarding en via de "?"-knop in het tradeformulier.
struct ScreenshotExampleView: View {

    var showsChecklist = true

    private typealias Strings = AppStrings.ScreenshotExample

    private let columns = [
        GridItem(.flexible(), spacing: 12, alignment: .topLeading),
        GridItem(.flexible(), spacing: 12, alignment: .topLeading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            mockScreenshot
            if showsChecklist {
                checklist
            }
        }
    }

    // MARK: - Nagebootst platformscherm

    private var mockScreenshot: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(Theme.textSecondary)
                Text(Strings.platformName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(Strings.orderHistory)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.elevated)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                field(Strings.columnSymbol, value: Strings.ticker, label: Strings.becomesTicker)
                field(Strings.columnSide, value: Strings.direction, label: Strings.becomesDirection, valueColor: Theme.profit)
                field(Strings.columnEntry, value: Strings.entry, label: Strings.becomesEntry)
                field(Strings.columnExit, value: Strings.exit, label: Strings.becomesExit)
                field(Strings.columnQuantity, value: Strings.quantity, label: Strings.becomesQuantity)
                field(Strings.columnPnL, value: Strings.pnl, label: Strings.becomesPnL, valueColor: Theme.profit)
                field(Strings.columnTimeIn, value: Strings.timeIn, label: Strings.becomesTimeIn)
                field(Strings.columnTimeOut, value: Strings.timeOut, label: Strings.becomesTimeOut)
            }
            .padding(12)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    /// Kolomkop zoals op het platform, de waarde gemarkeerd en een label
    /// met het veld in de app waar hij in terechtkomt.
    private func field(_ header: String, value: String, label: String, valueColor: Color = Theme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(header)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                )
            HStack(spacing: 3) {
                Image(systemName: "arrow.turn.down.right")
                Text(label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilitySummary: String {
        "\(Strings.title): \(Strings.ticker), \(Strings.direction), \(Strings.columnEntry) \(Strings.entry), \(Strings.columnExit) \(Strings.exit), \(Strings.columnQuantity) \(Strings.quantity), \(Strings.columnTimeIn) \(Strings.timeIn), \(Strings.columnTimeOut) \(Strings.timeOut), \(Strings.columnPnL) \(Strings.pnl)"
    }

    // MARK: - Checklist

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Strings.checklistTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(Strings.checklist)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 8) {
                ForEach(Strings.checklistItems, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.elevated)
                        .clipShape(Capsule())
                }
            }
            Label(Strings.tip, systemImage: "lightbulb")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Label(Strings.privacy, systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

/// Sheet met het voorbeeld, geopend via de "?"-knop bij de screenshot-import.
struct ScreenshotExampleSheetView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(AppStrings.ScreenshotExample.intro)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ScreenshotExampleView()
                }
                .padding(Theme.cardPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(AppStrings.ScreenshotExample.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.ScreenshotExample.done) { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ScreenshotExampleSheetView()
}
