Bouw een complete, native iOS day trading journal app in Swift/SwiftUI, geïnspireerd op TradeZella
(neem de functionaliteit over, niet de naam, logo of branding). De app wordt gesideload: er wordt
een UNSIGNED .ipa gebouwd via GitHub Actions, die ik zelf sign via Signulous. Lever een volledige,
werkende GitHub-repository op.

## 1. Technische basis
- Swift 5.10+, SwiftUI, minimaal iOS 17.0 (voor SwiftData en Swift Charts).
- Opslag: SwiftData, volledig lokaal/offline. Geen backend, geen accounts, geen login.
- GEEN capabilities die een betaald developer-profiel of speciale entitlements vereisen:
  geen iCloud/CloudKit, geen push notifications, geen App Groups, geen Sign in with Apple.
  Lokale notificaties (UNUserNotificationCenter) mogen wel.
- Gebruik XcodeGen: lever een `project.yml` aan in plaats van een handgeschreven .xcodeproj.
  Het .xcodeproj wordt in de CI gegenereerd. Commit geen .xcodeproj.
- Bundle identifier: `com.tradejournal.app` (makkelijk aan te passen in project.yml).
- Architectuur: MVVM, duidelijke mappenstructuur (Models, Views, ViewModels, Services,
  Utilities, Resources). Geen externe dependencies tenzij echt nodig (dan via Swift Package Manager).
- Dark mode als standaard, strak modern design in de stijl van TradeZella: kaarten met afgeronde
  hoeken, groen voor winst, rood voor verlies, veel data in één oogopslag.
- UI-taal: Nederlands, met gangbare Engelse tradingtermen (P&L, win rate, setup, bias, etc.).

## 2. GitHub Actions: unsigned IPA bouwen
Maak `.github/workflows/build-ipa.yml` die:
- draait op `macos-15` bij push naar `main`, bij tags `v*` en handmatig (workflow_dispatch);
- de nieuwste stabiele Xcode selecteert;
- XcodeGen installeert (`brew install xcodegen`) en `xcodegen generate` draait;
- bouwt met:
  xcodebuild -project TradeJournal.xcodeproj -scheme TradeJournal -sdk iphoneos
  -configuration Release -derivedDataPath build
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
- de .app in een map `Payload/` zet, zipt naar `TradeJournal.ipa`;
- de .ipa uploadt als build-artifact, en bij een tag `v*` ook als GitHub Release asset.
Voeg een README toe met stap-voor-stap uitleg: repo pushen → Actions → .ipa downloaden →
uploaden en signen in Signulous → installeren.

## 3. Datamodel (SwiftData)
- Account: naam, type (prop firm / live / demo / backtest), startbalans, broker, valuta.
- Trade: id, account, symbool/instrument, richting (long/short), entry datum+tijd, exit datum+tijd,
  entry prijs, exit prijs, aantal contracten/lots, stop loss, take profit, commissie/fees,
  bruto P&L, netto P&L (berekend), geplande risk in $, R-multiple (berekend), MAE/MFE (optioneel,
  handmatig), sessie (Asia/London/NY AM/NY PM, automatisch bepaald uit tijd met instelbare
  tijdzone), playbook/strategie, confluences (many-to-many), tags, fouten (mistakes), emotie
  vóór en na de trade, rating 1–5 sterren, notities (rich text of markdown), screenshots
  (meerdere afbeeldingen, uit Foto's of camera, lokaal opgeslagen), "regels gevolgd" ja/nee
  per playbook-regel.
- Ondersteun ook partial exits: een trade kan meerdere executions hebben; P&L wordt daarover berekend.
- Confluence: naam, categorie, kleur, icoon, actief/gearchiveerd.
- Playbook: naam, beschrijving, lijst met regels (checklist), gekoppelde standaard-confluences,
  voorbeeldscreenshots.
- DailyJournal: datum, pre-market plan, dagelijkse bias, nieuws/events, post-market review,
  mood, cijfer voor de dag, screenshots.
- Tag en Mistake: naam, kleur.

## 4. Confluences (kernfunctie)
Bij elke trade moet ik in één scherm snel kunnen aanvinken waarom ik de trade nam
(multi-select chips, gegroepeerd per categorie). Lever deze standaardset mee, volledig
bewerkbaar/uitbreidbaar/sorteerbaar in de instellingen:
- Bias: HTF bias bullish, HTF bias bearish, Daily bias, 4H bias, 1H bias, Weekly profile
- PD arrays: FVG, IFVG, Order Block, Breaker Block, Mitigation Block, Rejection Block,
  Volume Imbalance, BPR, Premium/Discount
- Liquiditeit: Sweep PDH, Sweep PDL, Sweep Asia high/low, Sweep London high/low,
  Equal highs/lows, Buy-side liquidity, Sell-side liquidity, Stop hunt
- Structuur: MSS, BOS, CISD, CHoCH, Displacement, SMT divergentie
- Tijd: London killzone, NY AM killzone, Silver Bullet, Macro, NY PM, Midnight open,
  8:30 open, 9:30 open
- Overig: Nieuws-event, OTE (Fibonacci), Standard deviation target
Elke confluence moet in de statistieken terugkomen (zie sectie 7).

## 5. Kalender (jaren aan data)
- Maandweergave zoals TradeZella: elk dagvakje toont netto P&L, aantal trades en win rate,
  groen/rood gekleurd, intensiteit schaalt met grootte van de P&L.
- Wekelijkse totalen in een kolom naast de kalender.
- Jaaroverzicht: 12 mini-maanden (heatmap-stijl), met totaal P&L per maand.
- Snel navigeren door meerdere jaren (jaarkiezer, swipe tussen maanden, "vandaag"-knop).
- Tik op een dag → dagdetail: alle trades van die dag, intraday cumulatieve P&L-grafiek,
  het daily journal van die dag, en snel een trade toevoegen.
- Moet soepel blijven werken met 5+ jaar en tienduizenden trades (gebruik efficiënte fetches,
  aggregatie per dag cachen).

## 6. Dashboard
- Filters bovenaan: account(s), periode (vandaag, week, maand, jaar, alles, custom),
  symbool, playbook, confluence.
- Kaarten: netto P&L, win rate, profit factor, gemiddelde winst / gemiddeld verlies,
  expectancy, gemiddelde R, aantal trades, grootste winst/verlies, max drawdown,
  huidige win/loss streak.
- Een samengestelde "trading score" (vergelijkbaar met de Zella Score) als radar/spider-chart
  op basis van win rate, profit factor, avg win/loss ratio, consistentie, drawdown en
  regels-gevolgd percentage.
- Grafieken (Swift Charts): cumulatieve equity curve, dagelijkse P&L bar chart,
  drawdown chart.
- Mini-kalender van de huidige maand en een lijst met recente trades.

## 7. Rapporten en analyse
Tabbladen met tabellen + grafieken, allemaal filterbaar:
- Per confluence: win rate, netto P&L, gemiddelde R, aantal trades.
- Per combinatie van confluences (bijv. "Sweep PDL + IFVG + NY AM killzone") gerangschikt op
  expectancy, zodat ik zie welke combinaties echt werken.
- Per playbook, per symbool, per richting (long vs short), per sessie, per dag van de week,
  per uur van de dag, per trade-duur, per tag, per mistake (hoeveel kostte elke fout).
- Emotie vs resultaat, rating vs resultaat.
- Vergelijkingsmodus: twee filtersets naast elkaar (bijv. met vs zonder SMT).

## 8. Trade log
- Doorzoekbare, sorteerbare lijst van alle trades met snelfilters.
- Swipe-acties: bewerken, dupliceren, verwijderen (met bevestiging).
- Tradedetail: alle velden, screenshots fullscreen met pinch-to-zoom, confluences als chips,
  checklist van het playbook met wat wel/niet gevolgd is.
- Trade toevoegen moet snel kunnen: slim formulier met standaardwaarden uit laatste trade,
  automatische berekening van P&L en R op basis van instrument (tick size / tick value
  instelbaar per symbool, met presets voor NQ, MNQ, ES, MES, YM, GC, CL en forex-paren).

## 9. Import en export (belangrijk bij sideloaden)
- CSV-import met kolommapping-scherm (zelf kolommen koppelen), met presets voor gangbare
  exports (Tradovate, NinjaTrader, TopstepX/ProjectX, MetaTrader, TradingView).
  Losse fills automatisch samenvoegen tot trades. Duplicaten detecteren.
- Volledige backup-export naar een .zip (JSON + alle screenshots) via de iOS share sheet /
  Bestanden-app, en volledige restore vanuit zo'n backup.
- Optionele automatische backup naar een door mij gekozen map in Bestanden
  (security-scoped bookmark), bijvoorbeeld bij elke app-start of dagelijks.
- CSV-export van trades.
Reden: bij opnieuw signen of certificaatintrekking kan lokale data verloren gaan,
dus backups moeten makkelijk en betrouwbaar zijn. Toon in de app een waarschuwing als de
laatste backup ouder is dan 7 dagen.

## 10. Extra TradeZella-achtige functies
- Daily journal met pre-market template en post-market review template (templates bewerkbaar).
- Progress tracker: dagelijkse regels (bijv. "max 3 trades", "stop na 2 verliezen",
  "journal ingevuld") afvinken, met streak- en consistentie-kalender.
- Doelen: maandelijks P&L-doel, max daily loss, max drawdown voor prop firm accounts,
  met voortgangsbalk en waarschuwing als ik dicht bij mijn daily loss limit zit.
- Backtest-modus: apart accounttype zodat backtest-trades de live statistieken niet vervuilen.
- Notebook: losse notities en lessen, te koppelen aan trades of dagen.
- Lokale herinneringen: bijvoorbeeld "vul je journal in" op een instelbaar tijdstip.
- Face ID / code-slot optioneel bij openen van de app (LocalAuthentication).

## 11. Kwaliteit
- Nette, gecommenteerde code, geen placeholders of TODO's in kernfunctionaliteit.
- Voorbeelddata-generator (achter een knop in de instellingen) die ~2 jaar aan realistische
  trades aanmaakt om kalender en rapporten te testen, plus een knop om alles te wissen.
- Unit tests voor P&L-, R- en statistiekberekeningen en voor de CSV-parser.
- De workflow moet in één keer groen draaien; controleer dat alle bestanden in project.yml
  worden meegenomen en dat de Info.plist de juiste keys bevat
  (NSPhotoLibraryUsageDescription, NSCameraUsageDescription, NSFaceIDUsageDescription).

Lever de volledige repository-inhoud op, bestand voor bestand, inclusief README.
