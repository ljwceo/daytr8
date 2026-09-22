import Foundation
import SwiftData

/// Voorbeelddata-generator: creëert ~2 jaar aan realistische trades en
/// biedt een "alles wissen"-functie om de database leeg te maken.
///
/// De generator is **deterministisch** (zaadwaarde is instelbaar) zodat
/// screenshots reproduceerbaar zijn en unit tests er tegen kunnen asserten.
///
/// Callers zijn zelf verantwoordelijk om de main-context vanaf de main thread aan te roepen.
public enum SampleDataService {

    public struct Options: Sendable {
        public var seed: UInt64
        public var years: Double
        public var tradesPerWeek: ClosedRange<Int>
        public var winRate: Double
        public var averageWinR: Double        // Gemiddelde win in R-multiples
        public var averageLossR: Double       // Gemiddelde loss in R (positief getal, wordt negatief gemaakt)
        public var breakevenChance: Double
        public var accountStartingBalance: Double

        public init(
            seed: UInt64 = 0xC0FFEE,
            years: Double = 2,
            tradesPerWeek: ClosedRange<Int> = 6...18,
            winRate: Double = 0.52,
            averageWinR: Double = 1.6,
            averageLossR: Double = 1.0,
            breakevenChance: Double = 0.06,
            accountStartingBalance: Double = 50_000
        ) {
            self.seed = seed
            self.years = years
            self.tradesPerWeek = tradesPerWeek
            self.winRate = winRate
            self.averageWinR = averageWinR
            self.averageLossR = averageLossR
            self.breakevenChance = breakevenChance
            self.accountStartingBalance = accountStartingBalance
        }

        public static let `default` = Options()
    }

    // MARK: - Publieke API

    /// Vult de database met een demo-account, één "backtest" account en ~2 jaar
    /// aan realistische trades. Vereist dat de presets en confluences al
    /// geseed zijn (`SeedService.seedDefaultsIfNeeded`).
    ///
    /// Bestaande data blijft staan; gebruik `wipeAll` om eerst leeg te maken.
    @discardableResult
    public static func generate(in context: ModelContext, options: Options = .default) -> Int {
        // Zorg dat presets en confluences aanwezig zijn.
        SeedService.seedDefaultsIfNeeded(in: context)

        let instruments = fetch(Instrument.self, in: context)
            .filter { ["NQ", "MNQ", "ES", "MES", "GC", "CL"].contains($0.symbol) }
        let confluences = fetch(Confluence.self, in: context)
        let calculator = SessionCalculator.default

        guard !instruments.isEmpty, !confluences.isEmpty else { return 0 }

        // Accounts
        let liveAccount = Account(
            name: "Demo Live",
            type: .demo,
            startingBalance: options.accountStartingBalance,
            broker: "Simulator",
            currency: "USD",
            maxDrawdown: 2_500,
            dailyLossLimit: 1_000,
            monthlyProfitTarget: 3_000
        )
        let backtestAccount = Account(
            name: "Backtest #1",
            type: .backtest,
            startingBalance: 25_000,
            broker: "Backtester",
            currency: "USD"
        )
        context.insert(liveAccount)
        context.insert(backtestAccount)

        // Playbook + regels
        let playbook = Playbook(
            name: "Silver Bullet",
            descriptionText: "Sweep + IFVG binnen de killzone.",
            iconName: "sparkles",
            colorHex: "#A46BF5"
        )
        context.insert(playbook)
        let rules = [
            "HTF bias bevestigd",
            "Sweep op sessie-liquiditeit",
            "IFVG / FVG als entry",
            "Killzone-tijd",
            "Stop achter zwaartepunt"
        ].enumerated().map { idx, text in
            let rule = PlaybookRule(text: text, sortOrder: idx * 10)
            rule.playbook = playbook
            context.insert(rule)
            return rule
        }

        // Tags & mistakes
        let tags = ["A+", "Setup B", "Nieuws"].map { name -> Tag in
            let t = Tag(name: name, colorHex: "#4C8BF5")
            context.insert(t); return t
        }
        let mistakes = [
            "Te vroeg entry",
            "Stop verplaatst",
            "Geen playbook",
            "Overtraded"
        ].map { name -> Mistake in
            let m = Mistake(name: name, colorHex: "#E0554D")
            context.insert(m); return m
        }

        // RNG
        var rng = SeededRandom(seed: options.seed)

        // Genereer trades vanaf ~options.years geleden tot vandaag.
        let now = Date()
        let secondsPerYear: TimeInterval = 365.25 * 24 * 3600
        let start = now.addingTimeInterval(-secondsPerYear * options.years)

        var day = normalizedDayStart(start, in: TimeZone(identifier: "America/New_York") ?? .current)
        var tradeCount = 0

        while day < now {
            let weekday = Calendar(identifier: .gregorian).component(.weekday, from: day)
            // 1 = Sun, 7 = Sat → skip weekend
            if weekday >= 2 && weekday <= 6 {
                let tradesToday = rng.int(in: 0...max(0, options.tradesPerWeek.upperBound / 3))
                for _ in 0..<tradesToday {
                    let inst = instruments.randomElement(using: &rng)!
                    let account = rng.double() < 0.15 ? backtestAccount : liveAccount

                    let entry = makeEntryDate(on: day, using: &rng)
                    let direction: TradeDirection = rng.double() < 0.5 ? .long : .short
                    let entryPrice = randomPrice(for: inst.symbol, using: &rng)
                    let stopDistanceTicks = Double(rng.int(in: 8...40))
                    let stopDistance = stopDistanceTicks * inst.tickSize
                    let stop = direction == .long ? entryPrice - stopDistance : entryPrice + stopDistance
                    let quantity: Double = inst.category == .microFuture ? Double(rng.int(in: 1...4))
                                                                          : Double(rng.int(in: 1...2))

                    // Beslis uitkomst
                    let roll = rng.double()
                    let outcomeR: Double
                    if roll < options.breakevenChance {
                        outcomeR = 0
                    } else if roll < options.breakevenChance + options.winRate * (1 - options.breakevenChance) {
                        outcomeR = options.averageWinR * rng.gaussian(mean: 1.0, sd: 0.35).clamped(to: 0.2...4.0)
                    } else {
                        outcomeR = -options.averageLossR * rng.gaussian(mean: 1.0, sd: 0.25).clamped(to: 0.4...1.6)
                    }

                    let priceMove = outcomeR * stopDistance * direction.sign
                    let exitPrice = entryPrice + priceMove
                    let holdMinutes = rng.int(in: 5...240)
                    let exitDate = entry.addingTimeInterval(TimeInterval(holdMinutes * 60))

                    let commission = 2.50 * quantity + (inst.category == .microFuture ? -1.7 * quantity : 0)
                    let fees = 0.50 * quantity

                    let trade = Trade(
                        symbol: inst.symbol,
                        direction: direction,
                        entryDate: entry,
                        exitDate: exitDate,
                        entryPrice: entryPrice,
                        exitPrice: exitPrice,
                        quantity: quantity,
                        stopLoss: stop,
                        takeProfit: direction == .long ? entryPrice + stopDistance * options.averageWinR
                                                       : entryPrice - stopDistance * options.averageWinR,
                        plannedRisk: nil,
                        mae: rng.double() * stopDistance,
                        mfe: max(0, priceMove * direction.sign) + rng.double() * stopDistance * 0.3,
                        commission: max(0.5, commission),
                        fees: fees,
                        tickSize: inst.tickSize,
                        tickValue: inst.tickValue,
                        emotionBefore: ["kalm", "scherp", "twijfelend"].randomElement(using: &rng)!,
                        emotionAfter: outcomeR > 0 ? "tevreden" : (outcomeR < 0 ? "gefrustreerd" : "neutraal"),
                        rating: rng.int(in: 2...5),
                        notes: "",
                        isBacktest: account.type == .backtest,
                        session: calculator.session(for: entry),
                        account: account,
                        instrument: inst,
                        playbook: playbook
                    )
                    context.insert(trade)

                    // Confluences: 2-5 random uit de standaardset
                    let confluenceCount = rng.int(in: 2...5)
                    trade.confluences = pickRandom(from: confluences, count: confluenceCount, using: &rng)

                    // Tags (0-2)
                    trade.tags = pickRandom(from: tags, count: rng.int(in: 0...2), using: &rng)

                    // Mistakes vaker bij verlies dan bij winst
                    let mistakeCount = outcomeR < 0 ? rng.int(in: 0...2) : rng.int(in: 0...1)
                    trade.mistakes = pickRandom(from: mistakes, count: mistakeCount, using: &rng)

                    // Rule adherence per playbook-regel
                    for rule in rules {
                        let followed = outcomeR >= 0 ? rng.double() < 0.9 : rng.double() < 0.6
                        let adherence = PlaybookRuleAdherence(followed: followed)
                        adherence.rule = rule
                        adherence.trade = trade
                        context.insert(adherence)
                    }

                    tradeCount += 1
                }
            }

            day = day.addingTimeInterval(24 * 3600)
        }

        do { try context.save() } catch {
            #if DEBUG
            print("SampleDataService.save error: \(error)")
            #endif
        }
        return tradeCount
    }

    /// Verwijdert **alle** door de app beheerde data (accounts, trades,
    /// executions, playbooks, journals, tags, mistakes, screenshots).
    /// De standaardconfluences en instrumentpresets worden op de volgende
    /// call van `SeedService.seedDefaultsIfNeeded` opnieuw aangemaakt.
    ///
    /// Gebruikt per type een batch-delete (`ModelContext.delete(model:)`), zodat
    /// de objecten niet eerst allemaal in het geheugen geladen worden. Eén voor
    /// één verwijderen was bij jaren aan data erg traag (elke trade werkt ook de
    /// many-to-many-lijsten van confluences/tags/mistakes bij) en kon de app
    /// laten vastlopen. Alleen als een batch-delete faalt, valt deze functie
    /// voor dat type terug op object-voor-object verwijderen.
    public static func wipeAll(in context: ModelContext) {
        // Volgorde: eerst kinderen, dan ouders.
        batchDelete(TradeExecution.self, in: context)
        batchDelete(TradeScreenshot.self, in: context)
        batchDelete(PlaybookRuleAdherence.self, in: context)
        batchDelete(Trade.self, in: context)
        batchDelete(PlaybookRule.self, in: context)
        batchDelete(Playbook.self, in: context)
        batchDelete(DailyJournalScreenshot.self, in: context)
        batchDelete(DailyJournal.self, in: context)
        batchDelete(Tag.self, in: context)
        batchDelete(Mistake.self, in: context)
        batchDelete(Confluence.self, in: context)
        batchDelete(Instrument.self, in: context)
        batchDelete(Account.self, in: context)

        do { try context.save() } catch {
            #if DEBUG
            print("SampleDataService.wipeAll error: \(error)")
            #endif
        }
    }

    // MARK: - Helpers

    private static func fetch<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    private static func batchDelete<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        do {
            try context.delete(model: type)
        } catch {
            #if DEBUG
            print("SampleDataService batch delete \(type) failed, fallback: \(error)")
            #endif
            for obj in fetch(type, in: context) {
                context.delete(obj)
            }
        }
    }

    private static func normalizedDayStart(_ date: Date, in tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.startOfDay(for: date)
    }

    private static func makeEntryDate(on day: Date, using rng: inout SeededRandom) -> Date {
        // Een entry ergens tussen 02:00 en 16:30 lokale (NY) tijd.
        let minute = rng.int(in: 2 * 60 ... (16 * 60 + 30))
        return day.addingTimeInterval(TimeInterval(minute * 60))
    }

    private static func randomPrice(for symbol: String, using rng: inout SeededRandom) -> Double {
        switch symbol {
        case "NQ", "MNQ":  return Double(rng.int(in: 15_000...20_000)) + Double(rng.int(in: 0...3)) * 0.25
        case "ES", "MES":  return Double(rng.int(in: 4_500...5_500))  + Double(rng.int(in: 0...3)) * 0.25
        case "YM", "MYM":  return Double(rng.int(in: 34_000...42_000))
        case "GC", "MGC":  return Double(rng.int(in: 1_900...2_400))  + Double(rng.int(in: 0...9)) * 0.1
        case "CL", "MCL":  return Double(rng.int(in: 60...95))        + Double(rng.int(in: 0...99)) * 0.01
        default:           return 100 + Double(rng.int(in: 0...9_999)) * 0.01
        }
    }

    private static func pickRandom<T>(from source: [T], count: Int, using rng: inout SeededRandom) -> [T] {
        guard !source.isEmpty, count > 0 else { return [] }
        var pool = source
        var picked: [T] = []
        let n = min(count, pool.count)
        for _ in 0..<n {
            let idx = rng.int(in: 0...(pool.count - 1))
            picked.append(pool.remove(at: idx))
        }
        return picked
    }
}

// MARK: - Deterministic RNG

/// Kleine PRNG (SplitMix64) — deterministisch én snel, en werkt met
/// Swift 5.10 zonder `RandomNumberGenerator`-mutation gedoe.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { self.state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }

    public mutating func int(in range: ClosedRange<Int>) -> Int {
        guard range.lowerBound <= range.upperBound else { return range.lowerBound }
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    public mutating func double() -> Double {
        // 53-bit mantissa
        let n = next() >> 11
        return Double(n) / Double(1 << 53)
    }

    /// Approximeert een normaal-verdeelde waarde via de gemiddelde-van-12-truc.
    public mutating func gaussian(mean: Double, sd: Double) -> Double {
        var sum: Double = 0
        for _ in 0..<12 { sum += double() }
        return mean + sd * (sum - 6.0)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
