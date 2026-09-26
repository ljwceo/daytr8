import SwiftUI
import Charts

/// Live (of licht vertraagde) koers van het laatst getrade instrument, met
/// dagverandering, tijdstip van de laatste koers en een intraday-sparkline.
struct LiveQuoteCardView: View {

    let viewModel: LiveQuoteViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Onderdelen

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(Theme.accent)
            Text(viewModel.quote?.symbol.display ?? viewModel.symbol?.display ?? "—")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            if let quote = viewModel.quote {
                if !quote.isMarketOpen {
                    badge("Markt gesloten", color: Theme.neutral)
                } else if quote.isDelayed {
                    badge("Vertraagd ±\(quote.delayMinutes) min", color: Theme.warning)
                } else {
                    badge("Live", color: Theme.profit)
                }
            }
            Spacer()
            if viewModel.phase == .loading {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let quote = viewModel.quote {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(price(quote.price, quote))
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    changeLabel(quote)
                }
                Spacer(minLength: 8)
                sparkline(quote)
                    .frame(width: 110, height: 44)
            }
            footer(quote)
        } else if case .failed(let message) = viewModel.phase {
            errorView(message)
        } else {
            Text("Koers ophalen…")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private func changeLabel(_ quote: LiveQuote) -> some View {
        if let change = quote.change, let fraction = quote.changeFraction {
            let sign = change > 0 ? "+" : ""
            Text("\(sign)\(price(change, quote)) (\(sign)\(fraction.formatted(.percent.precision(.fractionLength(2)))))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.color(forPnL: change))
        } else {
            Text("Verandering onbekend")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func footer(_ quote: LiveQuote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Laatste koers \(quote.lastUpdate.formatted(date: .omitted, time: .shortened)) · \(viewModel.sourceName)\(quote.isDelayed ? " · vertraagd" : "")")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            if case .failed(let message) = viewModel.phase {
                Label("Verversen mislukt: \(message)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 6) {
                Text("Koers niet beschikbaar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Button("Opnieuw proberen") {
                    Task { await viewModel.refresh() }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }
        }
    }

    @ViewBuilder
    private func sparkline(_ quote: LiveQuote) -> some View {
        if quote.points.count >= 2 {
            let prices = quote.points.map(\.price)
            let low = prices.min() ?? 0
            let high = prices.max() ?? 0
            let padding = max((high - low) * 0.1, abs(high) * 0.0001)
            let color = Theme.color(forPnL: quote.change ?? 0)
            Chart {
                ForEach(quote.points) { point in
                    LineMark(x: .value("Tijd", point.date), y: .value("Koers", point.price))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                if let previousClose = quote.previousClose, previousClose >= low - padding, previousClose <= high + padding {
                    RuleMark(y: .value("Vorig slot", previousClose))
                        .foregroundStyle(Theme.separator)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: (low - padding)...(high + padding))
            .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: Theme.smallCornerRadius).fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private func price(_ value: Double, _ quote: LiveQuote) -> String {
        let digits = quote.symbol.kind == .forex ? 5 : 2
        return value.formatted(.number.precision(.fractionLength(digits)))
    }
}
