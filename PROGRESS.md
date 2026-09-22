# Voortgang

## Fase 0 — Projectskelet & CI ✅

Doel: een lege, buildbare SwiftUI-app met de vijf top-level tabs, een dark thema,
een XcodeGen-projectdefinitie en een GitHub Actions-workflow die een unsigned
`.ipa` produceert. Nog geen features uit latere secties van `SPEC.md`.

### Aangemaakte / gewijzigde bestanden

Configuratie & CI
- `project.yml` — XcodeGen-projectdefinitie: iOS 17, Swift 5.10, bundle id
  `com.tradejournal.app`, Manual signing uit, `Info.plist`-pad + resources.
- `.github/workflows/build-ipa.yml` — draait op `macos-15` bij push naar `main`,
  bij `v*`-tags en handmatig; installeert XcodeGen, genereert het project,
  bouwt unsigned Release voor `iphoneos`, zipt de `.app` naar `TradeJournal.ipa`,
  uploadt als artifact en (bij tags) als Release-asset.
- `.gitignore` — sluit `*.xcodeproj`, `build/`, `DerivedData/`, `*.ipa`,
  `Payload/`, `.DS_Store`, SPM-artefacten enz. uit.

Docs
- `README.md` — installatie- en build-uitleg, stap voor stap installeren via
  Signulous.
- `CLAUDE.md` — architectuur- en code-afspraken (MVVM, mappen, naamgeving,
  kleuren, entitlement-beperkingen, per-fase werken).
- `PROGRESS.md` — dit bestand.

App-broncode (onder `TradeJournal/`)
- `App/TradeJournalApp.swift` — `@main`, root `RootTabView`, dark scheme, accent.
- `Views/RootTabView.swift` — TabView met vijf tabs (Dashboard, Kalender,
  Trades, Rapporten, Meer).
- `Views/PlaceholderView.swift` — herbruikbare placeholder voor lege tabs.
- `Views/Dashboard/DashboardView.swift` — placeholder.
- `Views/Calendar/CalendarView.swift` — placeholder.
- `Views/Trades/TradesView.swift` — placeholder.
- `Views/Reports/ReportsView.swift` — placeholder.
- `Views/More/MoreView.swift` — placeholder.
- `Utilities/Theme.swift` — kleuren (background, card, profit/loss/neutral,
  accent, warning), tekstkleuren en corner-radius/padding-constanten.
- `Models/.gitkeep`, `ViewModels/.gitkeep`, `Services/.gitkeep` — mappen bestaan
  al klaar voor fase 1.

Resources
- `Resources/Info.plist` — `UIUserInterfaceStyle = Dark`, iPhone required,
  usage descriptions:
  - `NSPhotoLibraryUsageDescription`
  - `NSPhotoLibraryAddUsageDescription`
  - `NSCameraUsageDescription`
  - `NSFaceIDUsageDescription`
- `Resources/Assets.xcassets/Contents.json`
- `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` — leeg 1024×1024
  slot (echte icon komt later).
- `Resources/Assets.xcassets/AccentColor.colorset/Contents.json` — accentkleur
  matching `Theme.accent`.

### Definition of done voor fase 0

- [x] Projectskelet volgens `SPEC.md` §1 (XcodeGen, mappen, `Info.plist`).
- [x] App met `TabView` en vijf placeholder-tabs, dark mode als default,
      kleurthema in `Utilities/Theme.swift`.
- [x] CI-workflow uit `SPEC.md` §2 die een unsigned `.ipa` bouwt en publiceert.
- [x] README met Signulous-installatie-uitleg.
- [x] `CLAUDE.md` met architectuurafspraken.
- [x] `PROGRESS.md` bijgewerkt.
- [x] Groene CI-run bevestigd.

## Fase 1 — SwiftData-datamodel, presets, statistieken & seed ✅

Doel: het complete datamodel uit `SPEC.md` §3 werkend krijgen, inclusief partial
exits, instrumentpresets (NQ, MNQ, ES, MES, YM, GC, CL, forex), de standaard
confluence-set uit §4, alle relevante berekeningen (P&L, R-multiple, win rate,
profit factor, expectancy, drawdown, streaks) in een testbare service, en
een voorbeelddata-generator die ~2 jaar aan trades produceert. Nog geen UI —
schermen komen in latere fases.

### Aangemaakte / gewijzigde bestanden

Configuratie
- `project.yml` — tweede target `TradeJournalTests` (unit-test bundle op iOS 17,
  ongesigneerd) toegevoegd, plus expliciete `schemes.TradeJournal` waarin
  alleen de app-target voor `build` gebruikt wordt zodat de CI-workflow
  niets extra's meebouwt. De tests worden via `xcodebuild test` (of Cmd+U
  in Xcode) uitgevoerd.

Nieuwe SwiftData-modellen (`TradeJournal/Models/`)
- `Enums.swift` — `AccountType`, `TradeDirection`, `Session`,
  `ConfluenceCategory`, `InstrumentCategory`, `TradeOutcome`.
- `Account.swift` — accountnaam, type, startbalans, broker, valuta, optionele
  prop-firm limits (`maxDrawdown`, `dailyLossLimit`), `monthlyProfitTarget`.
- `Instrument.swift` — verhandelbaar instrument met `tickSize`, `tickValue`,
  categorie en `pointValue`-helper. `isBuiltIn` markeert de meegeleverde presets.
- `Trade.swift` — volledige trade uit `SPEC.md §3` met snapshot-tick-info,
  `plannedRisk`, `mae`/`mfe`, playbook, confluences/tags/mistakes (many-to-many),
  screenshots en per-regel adherence.
- `TradeExecution.swift` — partial exits met signed quantity (positief = koop,
  negatief = verkoop) + eigen commissie/fees per fill.
- `TradeScreenshot.swift` — losse afbeelding bij een trade, extern opgeslagen.
- `Confluence.swift` — many-to-many gekoppeld aan `Trade` en `Playbook`.
- `Tag.swift`, `Mistake.swift` — losse labels + fouten (many-to-many op `Trade`).
- `Playbook.swift` — playbook + `PlaybookRule` (checklist) + `PlaybookRuleAdherence`
  (koppeling die per trade/regel bijhoudt of de regel gevolgd is).
- `DailyJournal.swift` — dagboek per handelsdag met pre-/post-market templates,
  mood, cijfer + `DailyJournalScreenshot`.
- `AppSchema.swift` — één plek waar alle `@Model`-types samenkomen voor
  `ModelContainer` en de tests.

Nieuwe services (`TradeJournal/Services/`)
- `InstrumentPresets.swift` — puur (geen SwiftData) — definities voor NQ, MNQ,
  ES, MES, YM, MYM, RTY, M2K, GC, MGC, SI, CL, MCL, NG en de grootste forex-paren
  (EURUSD, GBPUSD, AUDUSD, NZDUSD, USDCAD, USDCHF, USDJPY, EURJPY, GBPJPY).
- `DefaultConfluences.swift` — puur — de volledige standaardset uit `SPEC.md §4`
  (Bias, PD Arrays, Liquiditeit, Structuur, Tijd, Overig) met SF Symbol-iconen.
- `SessionCalculator.swift` — bepaalt Asia/London/NY AM/NY PM op basis van een
  instelbare tijdzone (standaard `America/New_York`) en aanpasbare tijdvensters.
- `StatsService.swift` — bruto/netto P&L (met en zonder executions), R-multiple,
  aggregatie (win rate, profit factor, expectancy, avg win/loss, largest win/loss,
  max drawdown + %, current/longest win/loss streak) en cumulatieve equity-curve.
- `SeedService.swift` — idempotent inschieten van instrumentpresets en
  standaardconfluences op de eerste app-start.
- `SampleDataService.swift` — deterministische generator (`SeededRandom`) die
  ~2 jaar aan realistische trades produceert (met accounts, playbook + regels,
  tags, mistakes, confluences en rule-adherence) én een `wipeAll` om de
  database volledig leeg te maken.

App-integratie
- `App/TradeJournalApp.swift` — bouwt één centrale `ModelContainer` met het
  volledige `AppSchema.models`, injecteert via `.modelContainer(...)` en
  draait `SeedService.seedDefaultsIfNeeded` in een `.task` op de root view.
- `Views/More/MoreView.swift` — voorlopige "Meer"-tab met een overzichts-sectie
  (aantallen accounts/trades/confluences/instrumenten) en drie debug-knoppen
  ("Standaarddata inschieten", "Voorbeelddata genereren", "Alles wissen" met
  bevestigingsdialoog).

Nieuwe test-target (`TradeJournalTests/`)
- `InstrumentPresetsTests.swift` — controleert dat NQ/MNQ/ES/MES/YM/GC/CL en de
  forex-paren aanwezig zijn, de tick-waarden matchen met de CME-specs en dat
  symbolen uniek zijn.
- `SessionCalculatorTests.swift` — 4 standaardvensters, inclusieve start /
  exclusieve eind, wrapping rond middernacht (Asia), buiten alle vensters →
  `.other`, tijdzone-conversie (Amsterdam → NY), custom configuratie.
- `StatsServiceTests.swift` — long/short win + loss, open trade, breakeven,
  R-multiple via plannedRisk én via stop-afstand, partial exits (volledig +
  gedeeltelijk gesloten), aggregatie (win rate/PF/expectancy/streaks/max DD),
  gemiddelde R-multiple, equity-curve, session-recompute.
- `SeedAndSampleDataTests.swift` — draait tegen een in-memory `ModelContainer`:
  seed insert-count matcht `InstrumentPresets`/`DefaultConfluences`, seed is
  idempotent, sample-generator produceert >50 trades met confluences + accounts,
  `wipeAll` maakt alles leeg, en de generator is deterministisch per seed.

### Definition of done voor fase 1

- [x] Alle SwiftData-modellen uit `SPEC.md §3` (inclusief partial exits en
      many-to-many relaties voor confluences/tags/mistakes).
- [x] Instrumentpresets voor NQ, MNQ, ES, MES, YM, GC, CL en de grootste forex-paren.
- [x] `StatsService` met de complete rekenkern (P&L, R, win rate, PF, expectancy,
      avg win/loss, max DD, streaks) en `SessionCalculator` met instelbare tijdzone.
- [x] Standaard confluence-set wordt bij de eerste start ingeschoten.
- [x] Voorbeelddata-generator (~2 jaar) en "alles wissen"-functie, bereikbaar
      via de Meer-tab.
- [x] Unit tests voor alle berekeningen en de seed/sample-data services.
- [x] `PROGRESS.md` en `CLAUDE.md` bijgewerkt.
- [x] Groene CI-run bevestigd (workflow_dispatch op deze branch).

## Fase 2 — Trade log & tradeformulier ✅

Doel: het trade log uit `SPEC.md §8` volledig werkend maken: een doorzoekbare,
sorteerbare lijst met snelfilters en swipe-acties, een tradedetail-scherm met
alle velden, en een slim tradeformulier voor zowel aanmaken als bewerken.

### Aangemaakte / gewijzigde bestanden

Nieuwe service (`TradeJournal/Services/`)
- `TradeEditingService.swift` — `FormValues`, een waarde-type met alle
  bewerkbare tradevelden, losstaand van SwiftData zodat het formulier live
  kan valideren en voorrekenen. `createTrade`/`update` schrijven `FormValues`
  weg (incl. confluences/tags/fouten en het herbouwen van de
  `PlaybookRuleAdherence`-rijen van het gekozen playbook), `duplicate` maakt
  een kopie met dezelfde setup maar lege resultaatvelden, `delete` verwijdert
  een trade, en `addScreenshot`/`removeScreenshot` beheren losse screenshots.
  `FormValues.makeDefault(basedOn:fallbackAccount:)` levert de
  standaardwaarden voor een nieuwe trade (account/instrument/symbool/
  richting/aantal/playbook overgenomen van de laatste trade).

Nieuwe viewmodels (`TradeJournal/ViewModels/`)
- `TradesListViewModel.swift` — zoekterm, snelfilter (alles/open/winst/
  verlies/deze week/deze maand), richtingsfilter en sortering
  (datum/P&L, op- of aflopend) als pure `filteredAndSorted(_:)`-functie;
  dupliceren/verwijderen gaan via `TradeEditingService`.
- `TradeFormViewModel.swift` — houdt `FormValues` bij voor zowel aanmaken
  (`.create`, geprefilld vanuit de laatste trade) als bewerken (`.edit(Trade)`).
  `livePreview` berekent P&L/R live door `StatsService` tegen een
  niet-opgeslagen `Trade` te draaien; `detectedSession` toont de
  automatisch bepaalde sessie. Toggle-helpers voor confluences/tags/fouten/
  playbook-regels, plus `pendingScreenshots` voor nieuwe, nog niet
  opgeslagen screenshots. `save(in:)` maakt aan of werkt bij.

Nieuwe/gewijzigde views (`TradeJournal/Views/Trades/`)
- `TradesView.swift` (was placeholder) — doorzoekbare (`.searchable`),
  sorteerbare `List` met snelfilter-chips, swipe-acties (verwijderen met
  bevestiging, dupliceren), toolbar-menu voor sorteren/richting, "+"-knop
  die `TradeFormView` als sheet opent, en `navigationDestination(for: Trade.self)`
  naar `TradeDetailView`.
- `TradeRowView.swift` — richting-icoon, symbool, datum/sessie en netto
  P&L/R-multiple (of "Open") per rij.
- `TradeDetailView.swift` — alle velden in kaarten (resultaat, prijzen/risk,
  confluence-chips, playbook-checklist met wel/niet gevolgd, tags/fouten,
  reflectie, screenshots), toolbar-menu (bewerken/dupliceren/verwijderen),
  screenshots tikken opent `ScreenshotViewerView`.
- `TradeFormView.swift` — live P&L/R/sessie-preview bovenaan; secties voor
  account, instrument (presets + handmatige tick size/value), richting/tijden
  (met "trade is gesloten"-toggle voor exit-velden), prijzen/risk, kosten,
  playbook + regel-checklist, confluences (gegroepeerd per categorie via
  `FlowLayout`), tags/fouten, reflectie (emotie/rating/notities) en
  screenshots (`PhotosPicker`, nieuw én bestaand, met verwijderen).
- `ScreenshotViewerView.swift` — fullscreen pager (`TabView` page-style) met
  pinch-to-zoom (`MagnificationGesture`) en dubbeltik-zoom per screenshot.

Nieuwe herbruikbare componenten (`TradeJournal/Views/Components/`)
- `ChipView.swift` — selecteerbare/alleen-lezen chip voor confluences, tags
  en fouten.
- `FlowLayout.swift` — eigen `Layout`-implementatie die chips laat omslaan
  naar een nieuwe regel, gegroepeerd per categorie.
- `StarRatingView.swift` — 1–5 sterren-rating (tik op huidige ster = wissen).

Utilities
- `Utilities/Theme.swift` — `Color(hex:)`-extensie toegevoegd om de
  `colorHex`-velden van confluences/tags/fouten om te zetten naar chipkleuren.

Nieuwe tests (`TradeJournalTests/`)
- `TradeEditingServiceTests.swift` — aanmaken (incl. sessie-herberekening,
  confluences/tags/rule-adherence), bijwerken (playbook wisselen herbouwt
  rule-adherence), dupliceren (setup blijft, resultaat wordt leeg),
  verwijderen (cascade naar screenshots), screenshots toevoegen/verwijderen,
  en `FormValues.makeDefault`.
- `TradesListViewModelTests.swift` — snelfilters (open/winst), richtingsfilter,
  zoeken op symbool/playbook/tag, sortering op datum en P&L.
- `TradeFormViewModelTests.swift` — validatie, live P&L/R-preview,
  instrumentpreset toepassen, confluence/tag/fout-toggles, playbook-regels
  resetten bij playbookwissel, opslaan in create- en edit-modus, prefill
  vanuit de laatste trade.

### Definition of done voor fase 2

- [x] Trade log: doorzoekbaar, sorteerbaar, snelfilters, swipe-acties
      (bewerken via navigatie naar detail, dupliceren, verwijderen met
      bevestiging).
- [x] Tradedetail: alle velden, screenshots fullscreen met pinch-to-zoom,
      confluence-chips, playbook-checklist met wel/niet gevolgd.
- [x] Tradeformulier: standaardwaarden uit de laatste trade, automatische
      P&L/R-berekening via instrumentpreset (tick size/value), sessie-
      autodetectie.
- [x] ViewModels + services voor aanmaken/bewerken/dupliceren, unit-getest
      zonder UI.
- [x] `PROGRESS.md` bijgewerkt.
- [ ] Groene CI-run bevestigen op deze branch (kan pas na een Mac-lokale of
      GitHub Actions-build; niet in deze sessie uitgevoerd).

## Volgende fase — Fase 3: Kalender & dashboard

Vooruitkijkend op basis van `SPEC.md §5` en `§6`:

- Kalender: maandweergave met netto P&L/aantal trades/win rate per dag,
  weektotalen, jaaroverzicht (heatmap), dagdetail met intraday-P&L-grafiek
  en snel een trade toevoegen.
- Dashboard: filters (account/periode/symbool/playbook/confluence), kaarten
  met de kernstatistieken, trading score (radar-chart), Swift Charts
  (equity curve, dagelijkse P&L, drawdown), mini-kalender en recente trades.
- Cache/aggregatie per dag zodat dit soepel blijft met jaren aan data.
