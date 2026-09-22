import Foundation

/// De standaard confluence-set uit SPEC.md §4.
/// Wordt op de eerste app-start ingeschoten en is daarna vrij te bewerken.
public enum DefaultConfluences {

    public struct Definition: Equatable, Sendable {
        public let name: String
        public let category: ConfluenceCategory
        public let icon: String
        public let sortOrder: Int

        public init(name: String, category: ConfluenceCategory, icon: String, sortOrder: Int) {
            self.name = name
            self.category = category
            self.icon = icon
            self.sortOrder = sortOrder
        }
    }

    /// Volledige lijst, gegroepeerd per categorie, in de volgorde uit SPEC.md §4.
    public static let all: [Definition] = [
        // Bias
        .init(name: "HTF bias bullish",    category: .bias, icon: "arrow.up.right",    sortOrder: 10),
        .init(name: "HTF bias bearish",    category: .bias, icon: "arrow.down.right",  sortOrder: 20),
        .init(name: "Daily bias",          category: .bias, icon: "sun.max",           sortOrder: 30),
        .init(name: "4H bias",             category: .bias, icon: "clock.arrow.circlepath", sortOrder: 40),
        .init(name: "1H bias",             category: .bias, icon: "clock",             sortOrder: 50),
        .init(name: "Weekly profile",      category: .bias, icon: "calendar",          sortOrder: 60),

        // PD arrays
        .init(name: "FVG",                 category: .pdArrays, icon: "rectangle.split.3x1",         sortOrder: 110),
        .init(name: "IFVG",                category: .pdArrays, icon: "rectangle.split.3x1.fill",    sortOrder: 120),
        .init(name: "Order Block",         category: .pdArrays, icon: "square.stack.3d.up",          sortOrder: 130),
        .init(name: "Breaker Block",       category: .pdArrays, icon: "hammer",                      sortOrder: 140),
        .init(name: "Mitigation Block",    category: .pdArrays, icon: "square.stack",                sortOrder: 150),
        .init(name: "Rejection Block",     category: .pdArrays, icon: "hand.raised",                 sortOrder: 160),
        .init(name: "Volume Imbalance",    category: .pdArrays, icon: "waveform.path.ecg",           sortOrder: 170),
        .init(name: "BPR",                 category: .pdArrays, icon: "arrow.left.and.right.square", sortOrder: 180),
        .init(name: "Premium/Discount",    category: .pdArrays, icon: "chart.line.uptrend.xyaxis",   sortOrder: 190),

        // Liquiditeit
        .init(name: "Sweep PDH",           category: .liquidity, icon: "arrow.up.to.line",   sortOrder: 210),
        .init(name: "Sweep PDL",           category: .liquidity, icon: "arrow.down.to.line", sortOrder: 220),
        .init(name: "Sweep Asia high",     category: .liquidity, icon: "arrow.up.right.circle",   sortOrder: 230),
        .init(name: "Sweep Asia low",      category: .liquidity, icon: "arrow.down.right.circle", sortOrder: 240),
        .init(name: "Sweep London high",   category: .liquidity, icon: "arrow.up.right.square",   sortOrder: 250),
        .init(name: "Sweep London low",    category: .liquidity, icon: "arrow.down.right.square", sortOrder: 260),
        .init(name: "Equal highs",         category: .liquidity, icon: "equal.circle",       sortOrder: 270),
        .init(name: "Equal lows",          category: .liquidity, icon: "equal.circle.fill",  sortOrder: 280),
        .init(name: "Buy-side liquidity",  category: .liquidity, icon: "arrow.up.arrow.down",sortOrder: 290),
        .init(name: "Sell-side liquidity", category: .liquidity, icon: "arrow.down.arrow.up",sortOrder: 300),
        .init(name: "Stop hunt",           category: .liquidity, icon: "target",             sortOrder: 310),

        // Structuur
        .init(name: "MSS",                 category: .structure, icon: "arrow.turn.up.right",   sortOrder: 410),
        .init(name: "BOS",                 category: .structure, icon: "arrow.up.forward",      sortOrder: 420),
        .init(name: "CISD",                category: .structure, icon: "chevron.up.chevron.down", sortOrder: 430),
        .init(name: "CHoCH",               category: .structure, icon: "arrow.triangle.swap",   sortOrder: 440),
        .init(name: "Displacement",        category: .structure, icon: "bolt",                  sortOrder: 450),
        .init(name: "SMT divergentie",     category: .structure, icon: "arrow.left.arrow.right",sortOrder: 460),

        // Tijd
        .init(name: "London killzone",     category: .time, icon: "clock.badge",         sortOrder: 510),
        .init(name: "NY AM killzone",      category: .time, icon: "clock.badge.checkmark", sortOrder: 520),
        .init(name: "Silver Bullet",       category: .time, icon: "sparkles",            sortOrder: 530),
        .init(name: "Macro",               category: .time, icon: "hourglass",           sortOrder: 540),
        .init(name: "NY PM",               category: .time, icon: "moon",                sortOrder: 550),
        .init(name: "Midnight open",       category: .time, icon: "moon.stars",          sortOrder: 560),
        .init(name: "8:30 open",           category: .time, icon: "8.circle",            sortOrder: 570),
        .init(name: "9:30 open",           category: .time, icon: "9.circle",            sortOrder: 580),

        // Overig
        .init(name: "Nieuws-event",        category: .other, icon: "newspaper",          sortOrder: 610),
        .init(name: "OTE (Fibonacci)",     category: .other, icon: "chart.xyaxis.line",  sortOrder: 620),
        .init(name: "Standard deviation target", category: .other, icon: "ruler",        sortOrder: 630)
    ]

    /// Instantieert de standaardset als losstaande `Confluence`-objecten.
    /// De caller besluit of/hoe ze in de `ModelContext` opgenomen worden.
    public static func makeConfluences() -> [Confluence] {
        all.map { def in
            Confluence(
                name: def.name,
                category: def.category,
                iconName: def.icon,
                isActive: true,
                isBuiltIn: true,
                sortOrder: def.sortOrder
            )
        }
    }
}
