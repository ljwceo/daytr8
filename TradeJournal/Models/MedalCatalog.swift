import Foundation

/// Alle medailles van de app. De id's zijn stabiel ("categorie.niveau"),
/// want behaalde medailles worden op id bewaard (`MedalStore`).
enum MedalCatalog {

    static let all: [MedalDefinition] = {
        let standard = MedalTier.standardThresholds
        var result: [MedalDefinition] = []
        result += MedalCatalog.counting(.totalTrades, thresholds: standard) { "Log \(MedalCatalog.amount($0)) trades." }
        result += MedalCatalog.counting(.winningTrades, thresholds: standard) { "Sluit \(MedalCatalog.amount($0)) trades met winst." }
        result += MedalCatalog.counting(.winStreak, thresholds: [3, 5, 7, 10, 15, 20, 25, 30, 40, 50]) { "\(MedalCatalog.amount($0)) winnende trades op rij." }
        result += MedalCatalog.counting(.activeDays, thresholds: [3, 5, 10, 20, 30, 50, 75, 100, 150, 250]) {
            "Log \(MedalCatalog.amount($0)) handelsdagen op rij. Weekenden zonder trades breken de reeks niet."
        }
        result += MedalCatalog.counting(.journaling, thresholds: standard) { "\(MedalCatalog.amount($0)) trades met notities of screenshots." }
        result += MedalCatalog.counting(.riskManagement, thresholds: standard) { "\(MedalCatalog.amount($0)) trades met een stop-loss of gepland risico." }
        result += MedalCatalog.counting(.totalProfit, thresholds: standard.map { $0 * 100 }) { "Haal in totaal \(MedalCatalog.currency($0)) netto winst." }
        result += MedalCatalog.winRateMedals()
        result += MedalCatalog.specialMedals()
        return result
    }()

    static func definition(withID id: String) -> MedalDefinition? {
        byID[id]
    }

    static func definitions(in category: MedalCategory) -> [MedalDefinition] {
        all.filter { $0.category == category }
    }

    private static let byID: [String: MedalDefinition] = Dictionary(uniqueKeysWithValues: MedalCatalog.all.map { ($0.id, $0) })

    // MARK: - Opbouw

    private static func counting(_ category: MedalCategory, thresholds: [Double], detail: (Double) -> String) -> [MedalDefinition] {
        zip(MedalTier.allCases, thresholds).map { tier, threshold in
            MedalDefinition(
                id: "\(category.rawValue).\(tier.rawValue)",
                category: category,
                tier: tier,
                name: "\(tier.displayName) · \(category.shortTitle)",
                detail: detail(threshold),
                rule: .count(threshold),
                isHidden: false,
                systemImage: category.systemImage
            )
        }
    }

    /// Win rate-mijlpalen: hogere niveaus vragen een hogere win rate over meer trades.
    private static func winRateMedals() -> [MedalDefinition] {
        let steps: [(rate: Double, trades: Int)] = [
            (0.40, 20), (0.45, 30), (0.50, 50), (0.55, 100), (0.60, 100),
            (0.60, 250), (0.65, 250), (0.65, 500), (0.70, 500), (0.75, 1000)
        ]
        return zip(MedalTier.allCases, steps).map { tier, step in
            MedalDefinition(
                id: "\(MedalCategory.winRate.rawValue).\(tier.rawValue)",
                category: .winRate,
                tier: tier,
                name: "\(tier.displayName) · \(MedalCategory.winRate.shortTitle)",
                detail: "Win rate van minimaal \(Int(step.rate * 100))% over ten minste \(step.trades) gesloten trades.",
                rule: .winRate(rate: step.rate, minimumTrades: step.trades),
                isHidden: false,
                systemImage: MedalCategory.winRate.systemImage
            )
        }
    }

    private static func specialMedals() -> [MedalDefinition] {
        [
            specialMedal(.firstTrade, tier: .koper, name: "Eerste trade", detail: "Log je allereerste trade.", hidden: false, image: "flag.checkered"),
            specialMedal(.comeback, tier: .zilver, name: "Comeback", detail: "Een winnende trade direct na 3 of meer verliezen op rij.", hidden: true, image: "arrow.uturn.up"),
            specialMedal(.nightOwl, tier: .saffier, name: "Nachtbraker", detail: "Open een trade tussen 22:00 en 05:00.", hidden: true, image: "moon.stars.fill"),
            specialMedal(.perfectWeek, tier: .goud, name: "Perfecte week", detail: "Een week met minstens 5 gesloten trades en geen enkel verlies.", hidden: true, image: "crown.fill"),
            specialMedal(.homeRun, tier: .robijn, name: "Home run", detail: "Een trade van 5R of meer.", hidden: true, image: "bolt.fill")
        ]
    }

    private static func specialMedal(_ event: MedalEvent, tier: MedalTier, name: String, detail: String, hidden: Bool, image: String) -> MedalDefinition {
        MedalDefinition(
            id: "\(MedalCategory.special.rawValue).\(event.rawValue)",
            category: .special,
            tier: tier,
            name: name,
            detail: detail,
            rule: .event(event),
            isHidden: hidden,
            systemImage: image
        )
    }

    // MARK: - Opmaak

    static func amount(_ value: Double) -> String {
        Int(value).formatted(.number.grouping(.automatic))
    }

    static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}
