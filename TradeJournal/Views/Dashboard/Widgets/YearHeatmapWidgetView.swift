import SwiftUI

/// Jaar-heatmap: maanden horizontaal, dagen van de week verticaal, één
/// ronde stip per dag. Groot jaartal linksboven (met bladeren tussen jaren),
/// samenvattend getal rechtsboven en een legenda met kleurschaal onderaan.
///
/// Kleuren komen uit het actieve thema (`Theme.scaleColor`). Getekend in één
/// `Canvas` (geen view per dag) en de dagwaarden zijn per jaar gecachet,
/// zodat het ook met meerdere jaren data soepel blijft.
struct YearHeatmapWidgetView: View {

    let context: WidgetRenderContext

    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var availableWidth: CGFloat = 0

    private let calendar = Calendar.current
    private let monthLabelHeight: CGFloat = 14
    private var metric: WidgetSettings.HeatmapMetric { context.settings.heatmapMetric }

    var body: some View {
        let data = heatmapData
        let grid = context.cached("grid-\(year)") { YearHeatmapGrid(year: year, calendar: calendar) }

        VStack(alignment: .leading, spacing: 10) {
            header(data)
            if let grid {
                heatmap(grid: grid, data: data)
            }
            legend(data)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Data

    private var heatmapData: HeatmapYearData {
        let filter = context.dataService.effectiveFilter(base: context.baseFilter, settings: context.settings, includePeriod: false)
        let trades = context.cached("heatmap-trades") { context.dataService.trades(context.allTrades, matching: filter) }
        return context.cached("heatmap-\(year)") {
            context.dataService.heatmap(for: trades, year: year, metric: metric, calendar: calendar)
        }
    }

    private var currentYear: Int { calendar.component(.year, from: Date()) }

    private func firstYear(_ data: HeatmapYearData) -> Int {
        min(data.availableYears.first ?? currentYear, currentYear)
    }

    // MARK: - Kop

    private func header(_ data: HeatmapYearData) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Button {
                year -= 1
            } label: {
                Image(systemName: "chevron.left").font(.subheadline.weight(.semibold))
            }
            .disabled(year <= firstYear(data) || context.isPreview)
            .accessibilityLabel("Vorig jaar")

            Text(String(year))
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()

            Button {
                year += 1
            } label: {
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
            }
            .disabled(year >= max(currentYear, data.availableYears.last ?? currentYear) || context.isPreview)
            .accessibilityLabel("Volgend jaar")

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(summaryText(data))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(summaryColor(data))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(summaryLabel)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
    }

    private var summaryLabel: String {
        switch metric {
        case .netPnL: return "Netto P&L"
        case .tradeCount: return "Trades"
        case .winRate: return "Win rate"
        case .rMultiple: return "Behaalde R"
        }
    }

    private func summaryText(_ data: HeatmapYearData) -> String {
        guard let summary = data.summary else { return "—" }
        switch metric {
        case .netPnL: return WidgetFormat.money(summary, context.currency)
        case .tradeCount: return String(format: "%.0f", summary)
        case .winRate: return WidgetFormat.percent(summary)
        case .rMultiple: return WidgetFormat.rMultiple(summary)
        }
    }

    private func summaryColor(_ data: HeatmapYearData) -> Color {
        guard let summary = data.summary else { return Theme.textTertiary }
        switch metric {
        case .netPnL, .rMultiple: return Theme.color(forPnL: summary)
        case .winRate: return Theme.color(forPnL: summary - 0.5)
        case .tradeCount: return Theme.textPrimary
        }
    }

    // MARK: - Raster

    private func cellSize(for grid: YearHeatmapGrid) -> CGFloat {
        let fitting = (availableWidth - Theme.heatmapLabelWidth) / CGFloat(max(grid.columnCount, 1))
        return max(Theme.heatmapMinCellSize, fitting)
    }

    private func heatmap(grid: YearHeatmapGrid, data: HeatmapYearData) -> some View {
        let cell = cellSize(for: grid)
        let width = Theme.heatmapLabelWidth + cell * CGFloat(grid.columnCount)
        let height = monthLabelHeight + cell * CGFloat(YearHeatmapGrid.rowCount)

        // Kleuren in `body` lezen (niet in de Canvas-closure), zodat een
        // themawissel de heatmap opnieuw tekent.
        let dayColors: [Color] = grid.days.map { day in
            guard let normalized = data.normalizedValue(for: day) else { return Theme.heatmapEmpty }
            return Theme.scaleColor(normalized, diverging: data.isDiverging)
        }
        let labelColor = Theme.textTertiary
        let todayColor = Theme.accent
        let today = calendar.startOfDay(for: Date())
        let monthSymbols = calendar.shortMonthSymbols
        let weekdaySymbols = calendar.veryShortWeekdaySymbols
        let firstWeekday = calendar.firstWeekday

        return ScrollView(.horizontal, showsIndicators: false) {
            Canvas { canvas, _ in
                let dot = cell * Theme.heatmapDotFraction
                for (index, day) in grid.days.enumerated() {
                    let position = grid.position(ofDayAt: index)
                    let origin = CGPoint(
                        x: Theme.heatmapLabelWidth + CGFloat(position.column) * cell + (cell - dot) / 2,
                        y: monthLabelHeight + CGFloat(position.row) * cell + (cell - dot) / 2
                    )
                    let rect = CGRect(origin: origin, size: CGSize(width: dot, height: dot))
                    canvas.fill(Path(ellipseIn: rect), with: .color(dayColors[index]))
                    if day == today {
                        canvas.stroke(Path(ellipseIn: rect.insetBy(dx: -1, dy: -1)), with: .color(todayColor), lineWidth: 1)
                    }
                }
                for marker in grid.monthMarkers {
                    let label = Text(monthSymbols[marker.month - 1]).font(.caption2).foregroundColor(labelColor)
                    canvas.draw(label, at: CGPoint(x: Theme.heatmapLabelWidth + CGFloat(marker.column) * cell, y: 0), anchor: .topLeading)
                }
                for row in stride(from: 0, to: YearHeatmapGrid.rowCount, by: 2) {
                    let symbol = weekdaySymbols[(firstWeekday - 1 + row) % 7]
                    let label = Text(symbol).font(.caption2).foregroundColor(labelColor)
                    canvas.draw(label, at: CGPoint(x: 0, y: monthLabelHeight + CGFloat(row) * cell + cell / 2), anchor: .leading)
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                openDay(at: location, grid: grid, cell: cell, data: data)
            }
            .allowsHitTesting(!context.isPreview)
            .accessibilityElement()
            .accessibilityLabel("Heatmap \(year), \(summaryLabel) \(summaryText(data))")
        }
        .defaultScrollAnchor(year == currentYear ? .trailing : .leading)
        .frame(height: height)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { availableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in availableWidth = width }
            }
        )
    }

    private func openDay(at location: CGPoint, grid: YearHeatmapGrid, cell: CGFloat, data: HeatmapYearData) {
        guard cell > 0 else { return }
        let column = Int(((location.x - Theme.heatmapLabelWidth) / cell).rounded(.down))
        let row = Int(((location.y - monthLabelHeight) / cell).rounded(.down))
        guard location.x >= Theme.heatmapLabelWidth, location.y >= monthLabelHeight,
              let day = grid.day(column: column, row: row), data.values[day] != nil else { return }
        context.onOpenDay(day)
    }

    // MARK: - Legenda

    private func legend(_ data: HeatmapYearData) -> some View {
        let steps: [Double] = data.isDiverging ? [-1, -0.5, 0, 0.5, 1] : [0.2, 0.4, 0.6, 0.8, 1]
        return HStack(spacing: 6) {
            Text(legendLow(data))
            HStack(spacing: 3) {
                ForEach(steps, id: \.self) { step in
                    Circle()
                        .fill(Theme.scaleColor(step, diverging: data.isDiverging))
                        .frame(width: Theme.heatmapMinCellSize * Theme.heatmapDotFraction, height: Theme.heatmapMinCellSize * Theme.heatmapDotFraction)
                }
            }
            Text(legendHigh(data))
            Spacer(minLength: 8)
            Circle()
                .fill(Theme.heatmapEmpty)
                .frame(width: Theme.heatmapMinCellSize * Theme.heatmapDotFraction, height: Theme.heatmapMinCellSize * Theme.heatmapDotFraction)
            Text("Geen trades")
        }
        .font(.caption2)
        .foregroundStyle(Theme.textTertiary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func legendLow(_ data: HeatmapYearData) -> String {
        switch metric {
        case .netPnL: return WidgetFormat.money(-data.maxMagnitude, context.currency)
        case .tradeCount: return "Minder"
        case .winRate: return "0%"
        case .rMultiple: return WidgetFormat.rMultiple(-data.maxMagnitude)
        }
    }

    private func legendHigh(_ data: HeatmapYearData) -> String {
        switch metric {
        case .netPnL: return WidgetFormat.money(data.maxMagnitude, context.currency)
        case .tradeCount: return "Meer (\(String(format: "%.0f", data.maxMagnitude)))"
        case .winRate: return "100%"
        case .rMultiple: return WidgetFormat.rMultiple(data.maxMagnitude)
        }
    }
}

/// Jaar-heatmap met één stip per dag.
struct YearHeatmapWidgetDefinition: DashboardWidgetDefinition {
    let type = DashboardWidgetType.yearHeatmap
    let title = "Jaar-heatmap"
    let systemImage = "circle.grid.3x3.fill"
    let summary = "Elke dag van het jaar als stip, gekleurd op P&L, aantal trades, win rate of R. Tik op een dag voor details."
    let defaultSize = WidgetSize.large
    let supportedSizes: [WidgetSize] = [.large]
    let options: WidgetSettingsOptions = [.accounts, .heatmapMetric]

    func makeContent(_ context: WidgetRenderContext) -> AnyView {
        AnyView(YearHeatmapWidgetView(context: context))
    }
}
