import Foundation
import SwiftData

/// Volledige backup en restore van het journal als `.zip`:
/// - `backup.json` — alle entiteiten als `BackupPayload` (met `formatVersion`);
/// - `images/<uuid>.<ext>` — alle screenshots van trades en daily journals.
///
/// Een restore vervangt de volledige database: eerst wordt de backup volledig
/// gelezen en gevalideerd, pas daarna wordt de bestaande data gewist en de
/// backup ingeladen. Zo blijft de huidige data intact als de backup onleesbaar
/// is.
public struct BackupService {

    public static let payloadPath = "backup.json"
    public static let imagesFolder = "images/"

    public enum BackupError: Error, Equatable, LocalizedError {
        case missingPayload
        case invalidPayload(String)
        case unsupportedVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .missingPayload:
                return "Dit is geen TradeJournal-backup (backup.json ontbreekt)."
            case .invalidPayload(let detail):
                return "De backup kon niet gelezen worden: \(detail)"
            case .unsupportedVersion(let version):
                return "Deze backup (formaatversie \(version)) is gemaakt met een nieuwere versie van de app. Werk de app eerst bij."
            }
        }
    }

    /// Korte samenvatting voor het bevestigingsscherm vóór een restore.
    public struct Summary: Equatable, Sendable {
        public let exportedAt: Date
        public let formatVersion: Int
        public let accountCount: Int
        public let tradeCount: Int
        public let journalCount: Int
        public let playbookCount: Int
        public let screenshotCount: Int
    }

    /// Een ingelezen, gevalideerde backup die klaar is om te herstellen.
    public struct LoadedBackup {
        public let payload: BackupPayload
        public let summary: Summary
        let reader: ZipReader
    }

    public init() {}

    // MARK: - Export

    /// Schrijft een volledige backup naar `directory` (standaard de tijdelijke
    /// map) en geeft de URL van het zip-bestand terug.
    @discardableResult
    public func exportBackup(
        from context: ModelContext,
        to directory: URL = FileManager.default.temporaryDirectory,
        fileNamePrefix: String = "TradeJournal-backup",
        now: Date = Date()
    ) throws -> URL {
        let url = directory.appendingPathComponent("\(fileNamePrefix)-\(CSVExportService.fileTimestamp(now)).zip")
        let writer = try ZipWriter(url: url, modificationDate: now)

        // Screenshots worden direct naar de zip gestreamd, zodat niet alle
        // afbeeldingen tegelijk in het geheugen staan.
        func writeImage(id: UUID, data: Data) throws -> String {
            let fileName = "\(id.uuidString).\(Self.fileExtension(for: data))"
            try writer.addFile(path: Self.imagesFolder + fileName, data: data, compress: false)
            return fileName
        }

        let accounts = fetch(Account.self, in: context)
        let instruments = fetch(Instrument.self, in: context)
        let confluences = fetch(Confluence.self, in: context)
        let tags = fetch(Tag.self, in: context)
        let mistakes = fetch(Mistake.self, in: context)
        let playbooks = fetch(Playbook.self, in: context)
        let trades = fetch(Trade.self, in: context)
        let journals = fetch(DailyJournal.self, in: context)

        var tradeDTOs: [BackupPayload.TradeDTO] = []
        tradeDTOs.reserveCapacity(trades.count)
        for trade in trades {
            var screenshots: [BackupPayload.ScreenshotDTO] = []
            for shot in trade.screenshots.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let fileName = try writeImage(id: shot.id, data: shot.imageData)
                screenshots.append(BackupPayload.ScreenshotDTO(id: shot.id, fileName: fileName, caption: shot.caption, sortOrder: shot.sortOrder, createdAt: shot.createdAt))
            }
            tradeDTOs.append(Self.dto(for: trade, screenshots: screenshots))
        }

        var journalDTOs: [BackupPayload.DailyJournalDTO] = []
        for journal in journals {
            var screenshots: [BackupPayload.ScreenshotDTO] = []
            for shot in journal.screenshots.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let fileName = try writeImage(id: shot.id, data: shot.imageData)
                screenshots.append(BackupPayload.ScreenshotDTO(id: shot.id, fileName: fileName, caption: shot.caption, sortOrder: shot.sortOrder, createdAt: shot.createdAt))
            }
            journalDTOs.append(BackupPayload.DailyJournalDTO(
                id: journal.id, date: journal.date,
                preMarketPlan: journal.preMarketPlan, dailyBias: journal.dailyBias,
                newsAndEvents: journal.newsAndEvents, postMarketReview: journal.postMarketReview,
                mood: journal.mood, dayRating: journal.dayRating,
                createdAt: journal.createdAt, updatedAt: journal.updatedAt,
                screenshots: screenshots
            ))
        }

        // Arrays los opbouwen (met expliciete types) houdt de type-checker snel.
        let accountDTOs: [BackupPayload.AccountDTO] = accounts.map { account in
            BackupPayload.AccountDTO(
                id: account.id, name: account.name, type: account.typeRaw,
                startingBalance: account.startingBalance, broker: account.broker, currency: account.currency,
                maxDrawdown: account.maxDrawdown, dailyLossLimit: account.dailyLossLimit,
                monthlyProfitTarget: account.monthlyProfitTarget,
                createdAt: account.createdAt, isArchived: account.isArchived
            )
        }
        let instrumentDTOs: [BackupPayload.InstrumentDTO] = instruments.map { instrument in
            BackupPayload.InstrumentDTO(
                id: instrument.id, name: instrument.name, symbol: instrument.symbol,
                category: instrument.categoryRaw, tickSize: instrument.tickSize, tickValue: instrument.tickValue,
                currency: instrument.currency, defaultQuantity: instrument.defaultQuantity,
                isBuiltIn: instrument.isBuiltIn, sortOrder: instrument.sortOrder, createdAt: instrument.createdAt
            )
        }
        let confluenceDTOs: [BackupPayload.ConfluenceDTO] = confluences.map { confluence in
            BackupPayload.ConfluenceDTO(
                id: confluence.id, name: confluence.name, category: confluence.categoryRaw,
                colorHex: confluence.colorHex, iconName: confluence.iconName, isActive: confluence.isActive,
                isBuiltIn: confluence.isBuiltIn, sortOrder: confluence.sortOrder,
                descriptionText: confluence.descriptionText
            )
        }
        let tagDTOs: [BackupPayload.LabelDTO] = tags.map { tag in
            BackupPayload.LabelDTO(id: tag.id, name: tag.name, colorHex: tag.colorHex, isBuiltIn: tag.isBuiltIn, createdAt: tag.createdAt)
        }
        let mistakeDTOs: [BackupPayload.MistakeDTO] = mistakes.map { mistake in
            BackupPayload.MistakeDTO(
                id: mistake.id, name: mistake.name, colorHex: mistake.colorHex,
                descriptionText: mistake.descriptionText, isBuiltIn: mistake.isBuiltIn, createdAt: mistake.createdAt
            )
        }
        let playbookDTOs: [BackupPayload.PlaybookDTO] = playbooks.map { playbook in
            let ruleDTOs: [BackupPayload.PlaybookRuleDTO] = playbook.rules
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { rule in BackupPayload.PlaybookRuleDTO(id: rule.id, text: rule.text, sortOrder: rule.sortOrder) }
            return BackupPayload.PlaybookDTO(
                id: playbook.id, name: playbook.name, descriptionText: playbook.descriptionText,
                iconName: playbook.iconName, colorHex: playbook.colorHex, isArchived: playbook.isArchived,
                createdAt: playbook.createdAt, rules: ruleDTOs,
                defaultConfluenceIDs: playbook.defaultConfluences.map(\.id)
            )
        }

        let payload = BackupPayload(
            formatVersion: BackupPayload.currentFormatVersion,
            exportedAt: now,
            appVersion: Self.appVersion,
            accounts: accountDTOs,
            instruments: instrumentDTOs,
            confluences: confluenceDTOs,
            tags: tagDTOs,
            mistakes: mistakeDTOs,
            playbooks: playbookDTOs,
            trades: tradeDTOs,
            dailyJournals: journalDTOs
        )

        try writer.addFile(path: Self.payloadPath, data: try Self.encoder.encode(payload), compress: true)
        try writer.finish()
        return url
    }

    // MARK: - Inlezen

    /// Leest en valideert een backup zonder iets aan de database te veranderen.
    public func loadBackup(at url: URL) throws -> LoadedBackup {
        let reader = try ZipReader(url: url)
        guard reader.contains(Self.payloadPath) else { throw BackupError.missingPayload }

        let payload: BackupPayload
        do {
            payload = try Self.decoder.decode(BackupPayload.self, from: try reader.data(for: Self.payloadPath))
        } catch let error as ZipArchive.ZipError {
            throw error
        } catch {
            throw BackupError.invalidPayload(error.localizedDescription)
        }

        guard payload.formatVersion >= 1 else {
            throw BackupError.invalidPayload("ongeldige formaatversie \(payload.formatVersion)")
        }
        guard payload.formatVersion <= BackupPayload.currentFormatVersion else {
            throw BackupError.unsupportedVersion(payload.formatVersion)
        }

        let screenshotCount = payload.trades.reduce(0) { $0 + $1.screenshots.count }
            + payload.dailyJournals.reduce(0) { $0 + $1.screenshots.count }
        let summary = Summary(
            exportedAt: payload.exportedAt,
            formatVersion: payload.formatVersion,
            accountCount: payload.accounts.count,
            tradeCount: payload.trades.count,
            journalCount: payload.dailyJournals.count,
            playbookCount: payload.playbooks.count,
            screenshotCount: screenshotCount
        )
        return LoadedBackup(payload: payload, summary: summary, reader: reader)
    }

    // MARK: - Restore

    /// Wist alle huidige data en laadt de backup in. Screenshots die in de zip
    /// ontbreken of beschadigd zijn worden overgeslagen i.p.v. de hele restore
    /// te laten mislukken.
    @discardableResult
    public func restore(_ backup: LoadedBackup, into context: ModelContext) throws -> Summary {
        let payload = backup.payload
        SampleDataService.wipeAll(in: context)

        var accounts: [UUID: Account] = [:]
        for dto in payload.accounts {
            let account = Account(
                id: dto.id, name: dto.name, type: AccountType(rawValue: dto.type) ?? .demo,
                startingBalance: dto.startingBalance, broker: dto.broker, currency: dto.currency,
                maxDrawdown: dto.maxDrawdown, dailyLossLimit: dto.dailyLossLimit,
                monthlyProfitTarget: dto.monthlyProfitTarget, createdAt: dto.createdAt, isArchived: dto.isArchived
            )
            context.insert(account)
            accounts[dto.id] = account
        }

        var instruments: [UUID: Instrument] = [:]
        for dto in payload.instruments {
            let instrument = Instrument(
                id: dto.id, name: dto.name, symbol: dto.symbol,
                category: InstrumentCategory(rawValue: dto.category) ?? .other,
                tickSize: dto.tickSize, tickValue: dto.tickValue, currency: dto.currency,
                defaultQuantity: dto.defaultQuantity, isBuiltIn: dto.isBuiltIn,
                sortOrder: dto.sortOrder, createdAt: dto.createdAt
            )
            context.insert(instrument)
            instruments[dto.id] = instrument
        }

        var confluences: [UUID: Confluence] = [:]
        for dto in payload.confluences {
            let confluence = Confluence(
                id: dto.id, name: dto.name, category: ConfluenceCategory(rawValue: dto.category) ?? .other,
                colorHex: dto.colorHex, iconName: dto.iconName, isActive: dto.isActive,
                isBuiltIn: dto.isBuiltIn, sortOrder: dto.sortOrder, descriptionText: dto.descriptionText
            )
            context.insert(confluence)
            confluences[dto.id] = confluence
        }

        var tags: [UUID: Tag] = [:]
        for dto in payload.tags {
            let tag = Tag(id: dto.id, name: dto.name, colorHex: dto.colorHex, isBuiltIn: dto.isBuiltIn, createdAt: dto.createdAt)
            context.insert(tag)
            tags[dto.id] = tag
        }

        var mistakes: [UUID: Mistake] = [:]
        for dto in payload.mistakes {
            let mistake = Mistake(
                id: dto.id, name: dto.name, colorHex: dto.colorHex,
                descriptionText: dto.descriptionText, isBuiltIn: dto.isBuiltIn, createdAt: dto.createdAt
            )
            context.insert(mistake)
            mistakes[dto.id] = mistake
        }

        var playbooks: [UUID: Playbook] = [:]
        var rules: [UUID: PlaybookRule] = [:]
        for dto in payload.playbooks {
            let playbook = Playbook(
                id: dto.id, name: dto.name, descriptionText: dto.descriptionText,
                iconName: dto.iconName, colorHex: dto.colorHex, isArchived: dto.isArchived, createdAt: dto.createdAt
            )
            context.insert(playbook)
            var playbookRules: [PlaybookRule] = []
            for ruleDTO in dto.rules {
                let rule = PlaybookRule(id: ruleDTO.id, text: ruleDTO.text, sortOrder: ruleDTO.sortOrder)
                context.insert(rule)
                playbookRules.append(rule)
                rules[ruleDTO.id] = rule
            }
            playbook.rules = playbookRules
            playbook.defaultConfluences = dto.defaultConfluenceIDs.compactMap { confluences[$0] }
            playbooks[dto.id] = playbook
        }

        for dto in payload.trades {
            let trade = Trade(
                id: dto.id, symbol: dto.symbol, direction: TradeDirection(rawValue: dto.direction) ?? .long,
                entryDate: dto.entryDate, exitDate: dto.exitDate,
                entryPrice: dto.entryPrice, exitPrice: dto.exitPrice, quantity: dto.quantity,
                stopLoss: dto.stopLoss, takeProfit: dto.takeProfit, plannedRisk: dto.plannedRisk,
                mae: dto.mae, mfe: dto.mfe, commission: dto.commission, fees: dto.fees,
                tickSize: dto.tickSize, tickValue: dto.tickValue,
                emotionBefore: dto.emotionBefore, emotionAfter: dto.emotionAfter,
                rating: dto.rating, notes: dto.notes, isBacktest: dto.isBacktest,
                session: Session(rawValue: dto.session) ?? .other,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt
            )
            context.insert(trade)
            trade.account = dto.accountID.flatMap { accounts[$0] }
            trade.instrument = dto.instrumentID.flatMap { instruments[$0] }
            trade.playbook = dto.playbookID.flatMap { playbooks[$0] }
            trade.confluences = dto.confluenceIDs.compactMap { confluences[$0] }
            trade.tags = dto.tagIDs.compactMap { tags[$0] }
            trade.mistakes = dto.mistakeIDs.compactMap { mistakes[$0] }

            var executions: [TradeExecution] = []
            for exec in dto.executions {
                let execution = TradeExecution(
                    id: exec.id, date: exec.date, price: exec.price, signedQuantity: exec.signedQuantity,
                    commission: exec.commission, fees: exec.fees, note: exec.note
                )
                context.insert(execution)
                executions.append(execution)
            }
            trade.executions = executions

            var adherences: [PlaybookRuleAdherence] = []
            for item in dto.ruleAdherence {
                let adherence = PlaybookRuleAdherence(id: item.id, followed: item.followed)
                context.insert(adherence)
                adherence.rule = item.ruleID.flatMap { rules[$0] }
                adherences.append(adherence)
            }
            trade.ruleAdherence = adherences

            var screenshots: [TradeScreenshot] = []
            for shot in dto.screenshots {
                guard let data = image(named: shot.fileName, in: backup.reader) else { continue }
                let screenshot = TradeScreenshot(id: shot.id, imageData: data, caption: shot.caption, sortOrder: shot.sortOrder, createdAt: shot.createdAt)
                context.insert(screenshot)
                screenshots.append(screenshot)
            }
            trade.screenshots = screenshots
        }

        for dto in payload.dailyJournals {
            let journal = DailyJournal(
                id: dto.id, date: dto.date, preMarketPlan: dto.preMarketPlan, dailyBias: dto.dailyBias,
                newsAndEvents: dto.newsAndEvents, postMarketReview: dto.postMarketReview,
                mood: dto.mood, dayRating: dto.dayRating, createdAt: dto.createdAt, updatedAt: dto.updatedAt
            )
            context.insert(journal)
            var screenshots: [DailyJournalScreenshot] = []
            for shot in dto.screenshots {
                guard let data = image(named: shot.fileName, in: backup.reader) else { continue }
                let screenshot = DailyJournalScreenshot(id: shot.id, imageData: data, caption: shot.caption, sortOrder: shot.sortOrder, createdAt: shot.createdAt)
                context.insert(screenshot)
                screenshots.append(screenshot)
            }
            journal.screenshots = screenshots
        }

        try context.save()
        return backup.summary
    }

    // MARK: - Helpers

    private func image(named fileName: String, in reader: ZipReader) -> Data? {
        // Alleen platte bestandsnamen binnen images/ accepteren.
        guard !fileName.isEmpty, !fileName.contains("/"), !fileName.contains("..") else { return nil }
        return try? reader.data(for: Self.imagesFolder + fileName)
    }

    private func fetch<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    static func dto(for trade: Trade, screenshots: [BackupPayload.ScreenshotDTO]) -> BackupPayload.TradeDTO {
        let executions: [BackupPayload.ExecutionDTO] = trade.executions
            .sorted { $0.date < $1.date }
            .map { exec in
                BackupPayload.ExecutionDTO(
                    id: exec.id, date: exec.date, price: exec.price, signedQuantity: exec.signedQuantity,
                    commission: exec.commission, fees: exec.fees, note: exec.note
                )
            }
        let adherence: [BackupPayload.RuleAdherenceDTO] = trade.ruleAdherence.map { item in
            BackupPayload.RuleAdherenceDTO(id: item.id, ruleID: item.rule?.id, followed: item.followed)
        }
        return BackupPayload.TradeDTO(
            id: trade.id, createdAt: trade.createdAt, updatedAt: trade.updatedAt,
            symbol: trade.symbol, direction: trade.directionRaw,
            entryDate: trade.entryDate, exitDate: trade.exitDate,
            entryPrice: trade.entryPrice, exitPrice: trade.exitPrice, quantity: trade.quantity,
            stopLoss: trade.stopLoss, takeProfit: trade.takeProfit, plannedRisk: trade.plannedRisk,
            mae: trade.mae, mfe: trade.mfe, commission: trade.commission, fees: trade.fees,
            tickSize: trade.tickSize, tickValue: trade.tickValue,
            emotionBefore: trade.emotionBefore, emotionAfter: trade.emotionAfter,
            rating: trade.rating, notes: trade.notes, isBacktest: trade.isBacktest,
            session: trade.sessionRaw,
            accountID: trade.account?.id, instrumentID: trade.instrument?.id, playbookID: trade.playbook?.id,
            confluenceIDs: trade.confluences.map(\.id),
            tagIDs: trade.tags.map(\.id),
            mistakeIDs: trade.mistakes.map(\.id),
            executions: executions,
            ruleAdherence: adherence,
            screenshots: screenshots
        )
    }

    /// Bestandsextensie op basis van de magic bytes van de afbeelding.
    static func fileExtension(for data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.count >= 12, bytes[4...11].elementsEqual(Array("ftypheic".utf8)) { return "heic" }
        return "bin"
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    // MARK: - JSON

    /// ISO 8601 met fracties van seconden, zodat datums exact terugkomen.
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = fractional.date(from: text) ?? plain.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Ongeldige datum: \(text)")
        }
        return decoder
    }
}
