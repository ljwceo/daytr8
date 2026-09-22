import Foundation

/// Voegt losse fills samen tot complete trades.
///
/// Per symbool worden de fills chronologisch doorlopen en wordt de netto
/// positie bijgehouden. Een trade begint zodra de positie van 0 afwijkt en
/// eindigt zodra hij weer 0 is. Bijkopen en partial exits blijven dus binnen
/// dezelfde trade. Gaat een fill door 0 heen (bijv. long 1 → verkoop 3), dan
/// wordt die fill gesplitst: het sluitende deel eindigt de lopende trade, het
/// restant opent een nieuwe trade in de andere richting. Commissie en fees
/// worden daarbij naar rato verdeeld.
///
/// Posities die aan het eind van de fills nog open staan, worden als open
/// trade teruggegeven.
public enum FillAggregator {

    /// Marge voor floating-point afronding bij het vergelijken van posities.
    static let epsilon = 1e-9

    public static func aggregate(_ fills: [ImportedFill]) -> [ImportedTrade] {
        let bySymbol = Dictionary(grouping: fills.filter { abs($0.signedQuantity) > epsilon }) { $0.symbol.uppercased() }
        var trades: [ImportedTrade] = []

        for (_, symbolFills) in bySymbol {
            let sorted = symbolFills.sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.sourceRow < rhs.sourceRow
            }

            var position: Double = 0
            var current: [ImportedFill] = []

            for fill in sorted {
                var remaining = fill.signedQuantity
                while abs(remaining) > epsilon {
                    let isAdding = abs(position) <= epsilon || (position > 0) == (remaining > 0)
                    let portionQuantity: Double
                    if isAdding {
                        portionQuantity = remaining
                    } else {
                        let closing = min(abs(remaining), abs(position))
                        portionQuantity = remaining > 0 ? closing : -closing
                    }

                    current.append(portion(of: fill, quantity: portionQuantity))
                    position += portionQuantity
                    remaining -= portionQuantity

                    if abs(position) <= epsilon {
                        position = 0
                        if let trade = makeTrade(from: current) { trades.append(trade) }
                        current = []
                    }
                }
            }

            if !current.isEmpty, let open = makeTrade(from: current) {
                trades.append(open)
            }
        }

        return trades.sorted { lhs, rhs in
            if lhs.entryDate != rhs.entryDate { return lhs.entryDate < rhs.entryDate }
            return lhs.symbol < rhs.symbol
        }
    }

    // MARK: - Intern

    /// Deel van een fill met `quantity` (met teken); kosten naar rato.
    private static func portion(of fill: ImportedFill, quantity: Double) -> ImportedFill {
        let ratio = abs(fill.signedQuantity) > epsilon ? abs(quantity) / abs(fill.signedQuantity) : 1
        var part = fill
        part.signedQuantity = quantity
        part.commission = fill.commission * ratio
        part.fees = fill.fees * ratio
        return part
    }

    /// Bouwt een `ImportedTrade` uit de fills van één positie-cyclus.
    private static func makeTrade(from fills: [ImportedFill]) -> ImportedTrade? {
        guard let first = fills.first else { return nil }
        let direction: TradeDirection = first.signedQuantity > 0 ? .long : .short
        let entries = fills.filter { ($0.signedQuantity > 0) == (direction == .long) }
        let exits = fills.filter { ($0.signedQuantity > 0) != (direction == .long) }

        let entryQuantity = entries.reduce(0) { $0 + abs($1.signedQuantity) }
        let exitQuantity = exits.reduce(0) { $0 + abs($1.signedQuantity) }
        guard entryQuantity > epsilon else { return nil }

        let entryPrice = entries.reduce(0) { $0 + $1.price * abs($1.signedQuantity) } / entryQuantity
        let isClosed = abs(entryQuantity - exitQuantity) <= epsilon
        let exitPrice: Double? = isClosed && exitQuantity > epsilon
            ? exits.reduce(0) { $0 + $1.price * abs($1.signedQuantity) } / exitQuantity
            : nil

        var sourceRows: [Int] = []
        for fill in fills where !sourceRows.contains(fill.sourceRow) {
            sourceRows.append(fill.sourceRow)
        }

        return ImportedTrade(
            symbol: first.symbol,
            direction: direction,
            quantity: entryQuantity,
            entryDate: entries.map(\.date).min() ?? first.date,
            exitDate: isClosed ? exits.map(\.date).max() : nil,
            entryPrice: entryPrice,
            exitPrice: exitPrice,
            commission: fills.reduce(0) { $0 + $1.commission },
            fees: fills.reduce(0) { $0 + $1.fees },
            fills: fills,
            sourceRows: sourceRows
        )
    }
}
