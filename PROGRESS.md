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

## Fase 3 — Kalender & dashboard ✅

Doel: `SPEC.md §5` (kalender) en `§6` (dashboard) werkend krijgen bovenop het
datamodel en de statistiek-services uit fase 1 en het trade-log/formulier uit
fase 2. Geen wijzigingen aan Rapporten (§7) — dat is fase 4.

### Aangemaakte / gewijzigde bestanden

Nieuwe services (`TradeJournal/Services/`)
- `CalendarAggregationService.swift` — groepeert trades in één O(n)-pas naar
  `DayAggregate` (netto/bruto P&L, aantal trades, win/loss/breakeven/open,
  win rate) per dag en rolt die op naar `MonthAggregate` per maand. Dagcellen
  doen daarna alleen nog een O(1) dictionary-lookup in plaats van de volledige
  tradelijst te filteren — dat is de "cache per dag" uit de spec, zonder een
  aparte tussen-renders bewaarde cache-laag die dit stadium van de app nog
  niet nodig heeft.
- `TradingScoreService.swift` — samengestelde trading score (zoals de Zella
  Score): 6 assen van 0-100 (win rate, profit factor, avg win/loss,
  consistentie, drawdown, regels-gevolgd) plus een gemiddelde. Alle formules
  zijn expliciet gedocumenteerde heuristieken (geen officiële formule
  gepubliceerd).
- `StatsService.swift` — `drawdownCurve(for:startingBalance:)` toegevoegd:
  cumulatieve drawdown (piek − equity) op basis van de bestaande
  `equityCurve`, voor de drawdown-grafiek op het dashboard.

Nieuwe viewmodels (`TradeJournal/ViewModels/`)
- `CalendarViewModel.swift` — UI-state (getoonde maand/jaar, geselecteerde
  dag, jaaroverzicht aan/uit) plus zuivere rasterlogica (`weeks`,
  `weekTotal`, navigatie). Houdt zelf geen trades vast.
- `DashboardViewModel.swift` — filters (accounts, periode, symbool,
  playbook, confluence) en pure afleidingen: gefilterde trades, statistieken,
  `equityPoints`/`drawdownPoints`/`dailyPnLPoints` (`DateValuePoint`),
  trading score, rule-adherence-rate, recente trades.
- `DayDetailViewModel.swift` — trades van één dag (op exit-dag, of entry-dag
  als nog open), intraday cumulatieve P&L, en het aanmaken/bijwerken van het
  `DailyJournal` van die dag (leeg concept wordt niet opgeslagen).
- `TradeFormViewModel.swift` / `Views/Trades/TradeFormView.swift` —
  `initialDate` parameter toegevoegd zodat "snel een trade toevoegen" vanuit
  de dagdetail start op de gekozen kalenderdag i.p.v. vandaag.

Nieuwe kalenderschermen (`TradeJournal/Views/Calendar/`)
- `CalendarView.swift` — maandweergave met "vandaag"-knop, swipe + pijltjes
  tussen maanden, toggle naar het jaaroverzicht, navigatie naar `DayDetailView`.
- `CalendarMonthGridView.swift` — dagraster + weektotalen-kolom.
- `CalendarDayCellView.swift` — dagvakje met netto P&L/aantal trades,
  achtergrondintensiteit schaalt met de grootte van de P&L.
- `YearHeatmapView.swift` — 12 mini-maanden (dag-heatmap + maandtotaal),
  tikken springt naar die maand.
- `DayDetailView.swift` — samenvatting, intraday-P&L-grafiek (bij >1 trade),
  tradelijst van de dag, dagjournal-editor (pre-market plan, bias, nieuws,
  review, mood, cijfer) en "+" voor een nieuwe trade op die dag.

Nieuwe dashboardschermen (`TradeJournal/Views/Dashboard/`)
- `DashboardView.swift` — filterbalk, KPI-kaartenraster, trading score,
  equity curve, dagelijkse P&L, drawdown, mini-kalender, recente trades.
- `DashboardFilterBar.swift` — periode/account(s)/symbool/playbook/confluence
  als menu-chips.
- `StatCardView.swift` (in `Views/Components/`) — herbruikbare KPI-kaart.
- `TradingScoreRadarView.swift` — radar/spider-chart, zelf getekend met
  `Canvas` (Swift Charts heeft geen radar-chart-type).
- `EquityCurveChartView.swift` — lijn+vulling-grafiek, herbruikt voor zowel
  de dashboard-equitycurve, de drawdown-grafiek als de intraday-grafiek in
  `DayDetailView`.
- `DailyPnLChartView.swift` — staafdiagram per dag, groen/rood.
- `MiniCalendarView.swift` — compacte alleen-lezen maandkalender.
- `RecentTradesCardView.swift` — laatste trades uit de huidige selectie.

Utilities
- `Utilities/Theme.swift` — `compactCurrency(_:)` toegevoegd voor compacte
  $-notatie in kalendercellen en mini-kaarten.

Nieuwe tests (`TradeJournalTests/`)
- `CalendarAggregationServiceTests.swift` — groepering op exit-dag vs.
  entry-dag (open trades), meerdere trades op één dag, maand-rollup.
- `TradingScoreServiceTests.swift` — elke as afzonderlijk (win rate, profit
  factor incl. ∞/nil, avg win/loss, drawdown, consistentie incl. randgevallen,
  rule adherence) en het gemiddelde.
- `CalendarViewModelTests.swift` — weekraster (maandag-start, volledige
  maand), maand/jaar-navigatie, "vandaag", `selectMonth`, weektotalen.
- `DashboardViewModelTests.swift` — elk filter afzonderlijk, grafiekpunten,
  rule-adherence-rate, recente trades.
- `DayDetailViewModelTests.swift` — dag-filtering, intraday cumulatieve P&L,
  journal aanmaken/bijwerken/niet-opslaan-bij-leeg-concept.
- `StatsServiceTests.swift` — test voor `drawdownCurve` toegevoegd.

### Definition of done voor fase 3

- [x] Kalender: maandweergave met netto P&L/aantal trades/win rate per dag,
      weektotalen, jaaroverzicht (heatmap), snel navigeren (jaarkiezer, swipe,
      "vandaag").
- [x] Dagdetail: alle trades van die dag, intraday cumulatieve P&L-grafiek,
      het daily journal van die dag, en snel een trade toevoegen.
- [x] Dashboard: filters (account/periode/symbool/playbook/confluence),
      KPI-kaarten, trading score (radar-chart), Swift Charts (equity curve,
      dagelijkse P&L, drawdown), mini-kalender, recente trades.
- [x] Aggregatie per dag in één O(n)-pas i.p.v. per-cel filteren, zodat dit
      soepel blijft met jaren aan data.
- [x] Unit tests voor de nieuwe services en viewmodels.
- [x] `PROGRESS.md` bijgewerkt.
- [ ] Groene CI-run bevestigen op deze branch (kan pas na een Mac-lokale of
      GitHub Actions-build; niet in deze sessie uitgevoerd).

## Fase 4 — Rapporten en analyse ✅

Doel: `SPEC.md §7` werkend krijgen bovenop de filters/statistiek-services uit
fase 1 en 3: brede breakdown-rapportages (confluence, confluentiecombinaties,
playbook, symbool, richting, sessie, dag van de week, uur van de dag,
trade-duur, tag, mistake, emotie, rating), elk filterbaar, plus een
vergelijkingsmodus met twee filtersets naast elkaar.

### Aangemaakte / gewijzigde bestanden

Nieuwe service (`TradeJournal/Services/`)
- `ReportAggregationService.swift` — puur, geen SwiftData-mutaties. Eén
  generieke `group(_:keys:)`-helper (O(n) per dimensie) waar alle
  breakdown-methodes op leunen: `byConfluence`, `byConfluenceCombination`
  (paren van confluences die samen op een trade staan, gerangschikt op
  expectancy, gefilterd op `minTradeCount` om ruis eruit te halen),
  `byPlaybook`, `bySymbol`, `byDirection`, `bySession`, `byDayOfWeek`
  (maandag→zondag, los van `calendar.firstWeekday`), `byHourOfDay`,
  `byDuration` (buckets via `TradeDurationBucket`: <5 min t/m >4 uur, open
  trades tellen niet mee), `byTag`, `byMistake` (netto P&L per fout = wat de
  fout kost), `byEmotionBefore`/`byEmotionAfter` en `byRating` (1–5 sterren,
  ongewaardeerde trades tellen niet mee). Levert overal `GroupResult`
  (label, `TradeStatistics`, optionele kleur) terug.

Nieuwe viewmodel (`TradeJournal/ViewModels/`)
- `ReportsViewModel.swift` — `Tab`-enum voor de 14 breakdown-dimensies
  (met `isUserSortable`: dag/uur/duur/rating/combinaties hebben al een
  betekenisvolle volgorde en zijn niet door de gebruiker te sorteren),
  `SortKey` (netto P&L/win rate/aantal/expectancy/gem. R) +
  oplopend/aflopend. Hergebruikt bewust twee `DashboardViewModel`-instanties
  (`primaryFilter`/`secondaryFilter`) voor de filters én voor
  `DashboardFilterBar` als filter-UI in plaats van een eigen filter-stack te
  bouwen — zo blijft er precies één plek die trades filtert. `compareMode`
  schakelt tussen één en twee filtersets.

Nieuwe/gewijzigde views (`TradeJournal/Views/Reports/`)
- `ReportsView.swift` (was placeholder) — filterbalk (`DashboardFilterBar`,
  dubbel in vergelijkingsmodus), horizontale tabbladkiezer, per tabblad een
  staafdiagram + tabel; toolbar-knop schakelt vergelijkingsmodus (twee
  filtersets naast elkaar met eigen KPI-samenvatting en dubbele
  resultatentabel) aan/uit. Sorteermenu alleen zichtbaar voor sorteerbare
  tabbladen.
- `GroupResultRowView.swift` — rij met label(+kleurstip), aantal trades,
  win rate, netto P&L en gem. R; gebruikt in de enkele en dubbele
  (vergelijkings-)lijst.
- `GroupedBarChartView.swift` — horizontale staafdiagram van netto P&L per
  groep (Swift Charts `BarMark`), begrensd tot de eerste `maxBars` groepen.

Nieuwe tests (`TradeJournalTests/`)
- `ReportAggregationServiceTests.swift` — elke breakdown-dimensie
  afzonderlijk: groepering, uitsluiten van trades zonder waarde (geen
  playbook/confluences/emotie/rating/open trade), sortering/volgorde
  (maandag→zondag, uur oplopend, duur-buckets, rating oplopend,
  confluentiecombinaties op expectancy + `minTradeCount`-filter), en dat
  `byMistake` de kosten van een fout laat zien.
- `ReportsViewModelTests.swift` — primaire/secundaire filterset werken
  onafhankelijk, `groupResults` dispatcht naar de juiste service-methode,
  confluentiecombinaties negeren de sorteerinstellingen, sortering op
  netto P&L op- en aflopend, `isUserSortable` per tabblad.

### Definition of done voor fase 4

- [x] Tabbladen per confluence, confluentiecombinatie (op expectancy),
      playbook, symbool, richting, sessie, dag van de week, uur van de dag,
      trade-duur, tag en mistake — elk met tabel + staafdiagram, filterbaar.
- [x] Emotie (vooraf/achteraf) vs. resultaat, rating vs. resultaat.
- [x] Vergelijkingsmodus: twee filtersets naast elkaar.
- [x] Hergebruikt `StatsService`/`DashboardViewModel`-filters en
      `DashboardFilterBar`; nieuwe aggregatie-service in `Services/`.
- [x] Unit tests voor alle breakdown-dimensies en de viewmodel.
- [x] `PROGRESS.md` bijgewerkt.
- [x] Groene CI-run bevestigd (workflow_dispatch op deze branch, run #8:
      https://github.com/ljwceo/daytr8/actions/runs/35787506777). Run #7
      faalde eerst op een pre-existente bug uit fase 3 — `.frame(width:
      52, minHeight: 56)` in `CalendarMonthGridView.swift` is geen geldige
      SwiftUI-overload — gefixt door de aanroep in twee `.frame(...)`-
      modifiers te splitsen.

## Volgende fase — Fase 5: Import en export

Vooruitkijkend op basis van `SPEC.md §9`:

- CSV-import met kolommapping-scherm (zelf kolommen koppelen), presets voor
  Tradovate, NinjaTrader, TopstepX/ProjectX, MetaTrader, TradingView. Losse
  fills automatisch samenvoegen tot trades (`TradeExecution`). Duplicaten
  detecteren.
- Volledige backup-export naar `.zip` (JSON + screenshots) via de iOS share
  sheet / Bestanden-app, en volledige restore vanuit zo'n backup. Versienummer
  in de payload voor toekomstige migraties.
- Optionele automatische backup naar een gekozen map in Bestanden
  (security-scoped bookmark).
- CSV-export van trades.
- Waarschuwing in de app als de laatste backup ouder is dan 7 dagen.
