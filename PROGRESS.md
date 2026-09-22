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
- [ ] Groene CI-run — bevestigen zodra de branch gepusht is.

## Volgende fase — Fase 1: SwiftData-datamodel & app-container

Op basis van `SPEC.md` §3 (datamodel):

- `TradeJournalTests`-target toevoegen aan `project.yml`.
- SwiftData `@Model`-types: `Account`, `Trade`, `TradeExecution`, `Confluence`,
  `Playbook`, `PlaybookRule`, `DailyJournal`, `Tag`, `Mistake`, plus de bijbehorende
  enums (`AccountType`, `TradeDirection`, `Session`).
- `ModelContainer` opzetten in `TradeJournalApp` en injecteren via
  `.modelContainer(...)`.
- Rekenlogica op `Trade` (bruto/netto P&L, R-multiple, sessie-afleiding uit tijdzone)
  met bijbehorende unit tests.
- Voorbeelddata-generator (voorlopig achter een debug-knop in `MoreView`) om
  het model tijdens ontwikkeling te vullen.
