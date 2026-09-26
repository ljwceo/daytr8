import Foundation

/// Centrale teksten voor de onboarding, het themasysteem en het
/// screenshot-voorbeeld. Pas teksten hier aan; views verwijzen alleen naar
/// deze constanten.
enum AppStrings {

    static let appName = "TradeJournal"

    // MARK: - Welkomstmelding

    enum Welcome {
        static let title = "Welkom bij \(AppStrings.appName)!"
        static let message = "Tik hier voor een korte rondleiding."
        static let close = "Sluiten"
        static let closeAccessibility = "Welkomstmelding sluiten"
    }

    // MARK: - Onboarding

    enum Onboarding {
        static let next = "Volgende"
        static let skip = "Overslaan"
        static let close = "Sluiten"
        static func progress(step: Int, of total: Int) -> String {
            "Stap \(step) van \(total)"
        }

        // 1. Welkom
        static let welcomeTitle = "Welkom bij \(AppStrings.appName)"
        static let welcomeBody = "Leg je daytrades vast, ontdek patronen in je resultaten en word stap voor stap een betere trader. Alles blijft op je toestel."
        static let welcomeHighlights = [
            "Trades loggen in een paar tikken",
            "Kalender, statistieken en rapporten",
            "Volledig offline, zonder account"
        ]

        // 2. Navigatie
        static let navigationTitle = "Zo vind je je weg"
        static let navigationBody = "Onderin staan vijf tabs. Tik op een tab hieronder om te zien wat je er vindt."
        static let tabDashboard = "Je P&L, win rate, equity curve en trading score in één oogopslag."
        static let tabCalendar = "Elke handelsdag met resultaat, plus je dagjournal."
        static let tabTrades = "Al je trades. Met + voeg je een nieuwe trade toe."
        static let tabReports = "Analyse per setup, sessie, dag en confluence."
        static let tabMore = "Accounts, confluences, backup en instellingen zoals Thema."

        // 3. Confluences
        static let confluencesTitle = "Confluences"
        static let confluencesBody = "Confluences zijn meerdere signalen die dezelfde kant op wijzen, zoals een support-level, een trendlijn en een volume-spike. Hoe meer confluences, hoe sterker de setup."
        static let confluencesExamples = ["Support-level", "Trendlijn", "Volume-spike"]
        static let confluencesStrength = "Sterkte van de setup"
        static let confluencesWhere = "Aanvinken doe je in het tradeformulier onder Confluences. Eigen confluences toevoegen kan via Meer → Confluences."

        // 4. Thema's
        static let themesTitle = "Kies je thema"
        static let themesBody = "Pas het uiterlijk aan zoals jij wilt. Je kunt dit later altijd wijzigen via Meer → Thema."

        // 5. Trade toevoegen
        static let addTradeTitle = "Een trade toevoegen"
        static let addTradeBody = "Tik in de Trades-tab op +. Kies Uitgebreid of Snel en vul in wat je weet. Tik op een stap voor uitleg."
        static let addTradeSteps: [(title: String, detail: String)] = [
            ("Account & symbool", "Kies je account en een instrument-preset (bijv. NQ) of typ zelf een ticker."),
            ("Long of short", "Kies de richting van je trade."),
            ("Tijden in en uit", "Stel de entry-tijd in en zet 'Trade is gesloten' aan voor de exit-tijd."),
            ("Entry- en exitprijs", "De prijzen waarop je in- en uitstapte. P&L wordt live berekend."),
            ("Aantal", "Het aantal contracten, lots of aandelen."),
            ("Stop loss & take profit", "Optioneel, maar nodig voor je R-multiple. Geplande risk kan ook."),
            ("Kosten", "Commissie en fees, zodat je netto P&L klopt."),
            ("Confluences aanvinken", "Tik de signalen aan die je setup onderbouwden."),
            ("Playbook, tags & fouten", "Koppel je setup en label wat goed of fout ging."),
            ("Emotie & notities", "Emotie vóór en na, een rating en je notities."),
            ("Screenshots", "Voeg je chart toe om later terug te kijken.")
        ]

        // 6. Screenshot-import
        static let importTitle = "Importeren met screenshots"
        static let importBody = "Upload een screenshot van je broker of platform. De app leest de tradegegevens eruit, op je toestel. Controleer de velden en sla op."
        static let importWhere = "In het tradeformulier: 'Vul in vanuit screenshot'."

        // 7. Klaar
        static let doneTitle = "Klaar om te beginnen!"
        static let doneBody = "Log je eerste trade en ontdek wat werkt. Deze rondleiding vind je terug via Meer → Rondleiding opnieuw bekijken."
        static let firstTrade = "Eerste trade toevoegen"
        static let toDashboard = "Naar dashboard"
    }

    // MARK: - Thema's

    enum Themes {
        static let settingsTitle = "Thema"
        static let groupSolid = "Effen"
        static let groupPastel = "Pastel"
        static let preview = "Voorbeeld"
        static let previewAccount = "Vandaag"
        static let previewWin = "Winst"
        static let previewLoss = "Verlies"
        static let previewButton = "Trade toevoegen"
        static let previewFooter = "Winst- en verlieskleuren blijven in elk thema goed leesbaar (WCAG AA)."
        static let selectedAccessibility = "Geselecteerd"

        static let donker = "Donker"
        static let licht = "Licht"
        static let middernachtblauw = "Middernachtblauw"
        static let bosgroen = "Bosgroen"
        static let lavendel = "Lavendel"
        static let mint = "Mint"
        static let perzik = "Perzik"
        static let babyblauw = "Babyblauw"
    }

    // MARK: - Instellingen

    enum Settings {
        static let replayTour = "Rondleiding opnieuw bekijken"
    }

    // MARK: - Voorbeeld-screenshot

    enum ScreenshotExample {
        static let title = "Voorbeeld-screenshot"
        static let helpAccessibility = "Voorbeeld-screenshot bekijken"
        static let intro = "Zo ziet een goede screenshot eruit. De gemarkeerde velden herkent de app."
        static let platformName = "Voorbeeldplatform"
        static let orderHistory = "Orderhistorie"
        static let checklistTitle = "Checklist"
        static let checklist = "Zorg dat op je screenshot zichtbaar zijn: ticker, entry, exit, aantal en tijden."
        static let checklistItems = ["Ticker", "Entry", "Exit", "Aantal", "Tijden"]
        static let tip = "Tip: bijgesneden screenshots van de orderhistorie werken het best."
        static let privacy = "De tekst wordt op je toestel gelezen; er gaat niets naar internet."
        static let done = "Klaar"

        // Fictieve voorbeeldwaarden (geen echte broker).
        static let ticker = "EXMPL"
        static let direction = "Long"
        static let entry = "142,50"
        static let exit = "145,20"
        static let quantity = "100"
        static let timeIn = "09:35"
        static let timeOut = "10:12"
        static let pnl = "+€270"

        // Kolomkoppen op het nagebootste platform.
        static let columnSymbol = "Symbool"
        static let columnSide = "Kant"
        static let columnQuantity = "Aantal"
        static let columnEntry = "Entry"
        static let columnExit = "Exit"
        static let columnTimeIn = "Tijd in"
        static let columnTimeOut = "Tijd uit"
        static let columnPnL = "P&L"

        // Labels bij de markeringen.
        static let becomesTicker = "dit wordt Symbool"
        static let becomesDirection = "dit wordt Richting"
        static let becomesEntry = "dit wordt Entry"
        static let becomesExit = "dit wordt Exit"
        static let becomesQuantity = "dit wordt Aantal"
        static let becomesTimeIn = "dit wordt Entry-tijd"
        static let becomesTimeOut = "dit wordt Exit-tijd"
        static let becomesPnL = "dit wordt Netto P&L"
    }
}
