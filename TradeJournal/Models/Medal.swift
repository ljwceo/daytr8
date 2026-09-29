import Foundation

/// Niveau (materiaal) van een medaille, van laag naar hoog.
enum MedalTier: String, Codable, CaseIterable, Identifiable, Comparable, Sendable {
    case koper
    case brons
    case zilver
    case goud
    case platina
    case saffier
    case robijn
    case smaragd
    case diamant
    case obsidiaan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .koper: return "Koper"
        case .brons: return "Brons"
        case .zilver: return "Zilver"
        case .goud: return "Goud"
        case .platina: return "Platina"
        case .saffier: return "Saffier"
        case .robijn: return "Robijn"
        case .smaragd: return "Smaragd"
        case .diamant: return "Diamant"
        case .obsidiaan: return "Obsidiaan"
        }
    }

    /// 0 (koper) … 9 (obsidiaan).
    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// Drempels voor tellende categorieën (aantal trades, winsten, …).
    static let standardThresholds: [Double] = [5, 20, 50, 100, 250, 500, 750, 1000, 2500, 5000]

    var standardThreshold: Double { Self.standardThresholds[rank] }

    /// Materiaalkleuren (licht → donker) voor het medaille-icoon. Vast per
    /// materiaal, onafhankelijk van het thema; `Theme.medalGradient` maakt
    /// er kleuren van.
    var material: (light: HexColor, dark: HexColor) {
        switch self {
        case .koper: return (HexColor("#F0A57C"), HexColor("#8E4523"))
        case .brons: return (HexColor("#E3B27A"), HexColor("#7A5230"))
        case .zilver: return (HexColor("#F4F6F9"), HexColor("#8C96A3"))
        case .goud: return (HexColor("#FFE38A"), HexColor("#C38F12"))
        case .platina: return (HexColor("#EEF6F8"), HexColor("#7F9EAC"))
        case .saffier: return (HexColor("#8DB4FF"), HexColor("#1D3C9C"))
        case .robijn: return (HexColor("#FF8AA0"), HexColor("#9B1236"))
        case .smaragd: return (HexColor("#7BE8B0"), HexColor("#0B7446"))
        case .diamant: return (HexColor("#F0FDFF"), HexColor("#6CC7E0"))
        case .obsidiaan: return (HexColor("#7D6AA8"), HexColor("#140F1F"))
        }
    }

    /// Hoge niveaus krijgen een glans/gloed rond het icoon.
    var hasGlow: Bool { self >= .platina }

    static func < (lhs: MedalTier, rhs: MedalTier) -> Bool { lhs.rank < rhs.rank }
}

/// Categorie van medailles; elke categorie (behalve `special`) heeft een
/// medaille per `MedalTier`.
enum MedalCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case totalTrades
    case winningTrades
    case winStreak
    case activeDays
    case journaling
    case riskManagement
    case winRate
    case totalProfit
    case special

    var id: String { rawValue }

    var title: String {
        switch self {
        case .totalTrades: return "Trades gelogd"
        case .winningTrades: return "Winnende trades"
        case .winStreak: return "Win-streak"
        case .activeDays: return "Dagen op rij"
        case .journaling: return "Journaling-discipline"
        case .riskManagement: return "Risk management"
        case .winRate: return "Win rate"
        case .totalProfit: return "Totale winst"
        case .special: return "Speciaal"
        }
    }

    /// Korte naam voor op de medaille ("Goud · Trades").
    var shortTitle: String {
        switch self {
        case .totalTrades: return "Trades"
        case .winningTrades: return "Winsten"
        case .winStreak: return "Streak"
        case .activeDays: return "Dagen"
        case .journaling: return "Journal"
        case .riskManagement: return "Risk"
        case .winRate: return "Win rate"
        case .totalProfit: return "Winst"
        case .special: return "Speciaal"
        }
    }

    var systemImage: String {
        switch self {
        case .totalTrades: return "list.bullet.rectangle"
        case .winningTrades: return "arrow.up.right"
        case .winStreak: return "flame.fill"
        case .activeDays: return "calendar"
        case .journaling: return "square.and.pencil"
        case .riskManagement: return "shield.lefthalf.filled"
        case .winRate: return "percent"
        case .totalProfit: return "dollarsign"
        case .special: return "star.fill"
        }
    }
}

/// Eén medaille: wat je ervoor moet doen en hoe hij eruitziet.
struct MedalDefinition: Identifiable, Equatable, Hashable, Sendable {

    /// Voorwaarde, los van de categorie (die bepaalt alleen groepering/icoon).
    enum Rule: Equatable, Hashable, Sendable {
        /// Een tellende waarde moet `target` halen.
        case count(Double)
        /// Win rate ≥ `rate` (0…1) over minimaal `minimumTrades` gesloten trades.
        case winRate(rate: Double, minimumTrades: Int)
        /// Eenmalige gebeurtenis (speciale medailles).
        case event(MedalEvent)
    }

    let id: String
    let category: MedalCategory
    let tier: MedalTier
    let name: String
    let detail: String
    let rule: Rule
    /// Verborgen medailles tonen naam en beschrijving pas na het behalen.
    let isHidden: Bool
    let systemImage: String
}

/// Gebeurtenissen voor de speciale medailles.
enum MedalEvent: String, Codable, CaseIterable, Sendable {
    case firstTrade
    case comeback
    case nightOwl
    case perfectWeek
    case homeRun
}
