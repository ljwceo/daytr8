# CLAUDE.md — architectuur- en code-afspraken voor TradeJournal

Deze afspraken gelden voor **elke** sessie/fase in deze repo. Volg ze zodat de codebase
consistent blijft en de CI in één keer groen bouwt.

De volledige productspec staat in [`SPEC.md`](SPEC.md). De voortgang per fase in
[`PROGRESS.md`](PROGRESS.md). Werk PROGRESS.md aan het einde van elke fase bij.

## 1. Doel en beperkingen

- Native iOS-app in **Swift 5.10+ / SwiftUI**, iOS **17.0+**.
- Volledig **offline**: geen backend, geen accounts, geen login, geen analytics.
- **Geen** capabilities die een betaald Apple Developer Program vereisen:
  - géén iCloud / CloudKit
  - géén push notifications
  - géén App Groups
  - géén Sign in with Apple
  - géén Background Modes buiten wat SwiftData standaard doet
- Wél toegestaan: `UNUserNotificationCenter` (lokale notificaties), `LocalAuthentication`
  (Face ID / passcode), `PhotosUI`/`UIImagePickerController` (screenshots), Bestanden-app
  (security-scoped bookmarks voor backup).
- Als je twijfelt of een API een entitlement nodig heeft die Signulous niet kan geven:
  gebruik hem niet.

## 2. Projectstructuur & build

- Projectbestand wordt gegenereerd met **XcodeGen** uit `project.yml`.
  **Commit nooit** het `.xcodeproj` — dat maakt de CI.
- Bundle identifier: `com.tradejournal.app` (alleen wijzigen in `project.yml`).
- Alle Swift-bestanden staan onder `TradeJournal/` en worden automatisch opgepakt
  door de `sources: - path: TradeJournal`-regel in `project.yml`. Nieuwe bestanden
  hoef je dus niet handmatig aan `project.yml` toe te voegen — plaats ze in de
  juiste map en ze zitten in de build.
- `Info.plist` staat in `TradeJournal/Resources/Info.plist` en is de bron van
  waarheid voor usage descriptions. Voeg elke nieuwe systeem-permissie zowel daar
  als in `project.yml` (onder `info.properties`) toe, met een Nederlandse omschrijving.
- De CI-workflow (`.github/workflows/build-ipa.yml`) bouwt **unsigned** Release voor
  `iphoneos` en publiceert `TradeJournal.ipa` als artifact (en bij `v*`-tags als
  Release asset). Verander niets aan de code-signing-vlaggen daarin.

## 3. Mappenstructuur (MVVM)

```
TradeJournal/
├── App/            # @main + app-brede setup (WindowGroup, ModelContainer, root view)
├── Models/         # SwiftData @Model-types en waarde-types (bijv. enums, DTO's)
├── Views/          # SwiftUI-views, gegroepeerd per feature-map
│   ├── Dashboard/
│   ├── Calendar/
│   ├── Trades/
│   ├── Reports/
│   └── More/
├── ViewModels/     # @Observable viewmodels (één per non-triviaal scherm)
├── Services/       # SwiftData-store, CSV import/export, backup, notificaties, auth
├── Utilities/      # Theme, formatters, math-helpers, extensies
└── Resources/      # Info.plist, Assets.xcassets, eventueel .json seed-data
```

Regels:

- **Views** bevatten géén business logic en géén directe `ModelContext`-mutaties.
  Ze roepen de viewmodel of service aan.
- **ViewModels** zijn `@Observable` (Swift 5.9+ macro), stateless waar mogelijk,
  krijgen dependencies via de initializer.
- **Services** zijn `final class` of `struct`, geïsoleerd (bijv. `@MainActor` waar
  nodig voor SwiftData), en unit-testbaar zonder UI.
- **Models** blijven puur data + afgeleide berekeningen. Zware aggregaties horen
  in een service, niet in het model.
- Sub-views die alleen door één scherm gebruikt worden mogen in hetzelfde bestand
  blijven; herbruikbare componenten krijgen een eigen bestand onder `Views/` (of
  `Views/Components/` zodra er meerdere zijn).

## 4. Naamgeving

- Views eindigen op `View` (`DashboardView`, `TradeRowView`).
- ViewModels eindigen op `ViewModel` (`DashboardViewModel`).
- Services eindigen op hun rol (`TradeStore`, `CSVImportService`, `BackupService`).
- SwiftData-modellen zijn enkelvoud (`Trade`, `Account`, `Confluence`).
- Enums voor gesloten sets (bijv. `TradeDirection`, `Session`, `AccountType`) —
  `String, Codable, CaseIterable`, waardes lowercase.
- Bestandsnaam = type-naam.
- UI-taal is **Nederlands**; gangbare Engelse trading-termen (P&L, win rate, setup,
  bias, playbook, confluence, R-multiple, …) worden onvertaald overgenomen.
- Comments in code mogen Nederlands of Engels zijn — houd het per bestand consistent.

## 5. Styling & thema

- **Dark mode is standaard**. Zet `.preferredColorScheme(.dark)` alleen op de root;
  losse views doen het niet zelf.
- Gebruik altijd `Theme` uit `Utilities/Theme.swift` voor kleuren, hoekradii en
  paddings. **Geen** hardcoded `Color(...)` of magic numbers in views.
- Semantiek:
  - `Theme.profit` (groen) voor winst / positief resultaat
  - `Theme.loss` (rood) voor verlies / negatief resultaat
  - `Theme.neutral` voor breakeven
  - `Theme.accent` voor actieve tab, links, primaire knop
  - `Theme.warning` voor waarschuwingen (bijv. dicht bij daily loss limit)
- Kaarten: `Theme.card` achtergrond, `Theme.cornerRadius` (16pt), `Theme.cardPadding`
  (16pt). Kleine chips/badges: `Theme.smallCornerRadius` (10pt).
- Nieuwe kleur nodig? Zet hem in `Theme`, niet in de view.

## 6. Data-afhandeling

- Alle persistente data via **SwiftData** met één `ModelContainer` op app-niveau
  (aanmaken vanaf fase 1). Injecteer via `.modelContainer(...)` op de root scene
  en gebruik `@Environment(\.modelContext)` in views die het écht nodig hebben.
- Zware queries / aggregaties (kalender, rapporten) niet in views — bouw ze in
  een service en cache per dag/maand.
- Backup-/import-/export-formaat: JSON + losse afbeeldingen, verpakt in `.zip`.
  Houd het versienummer van het formaat in de payload op zodat migraties mogelijk zijn.

## 7. Testen

- Unit tests voor pure berekeningen (P&L, R-multiple, statistiek) en de CSV-parser.
  Testen komen vanaf fase 1 in een aparte `TradeJournalTests`-target die aan
  `project.yml` wordt toegevoegd.
- Geen UI-tests in de CI-pipeline (te traag / bros). Wel snapshots achter een
  aparte scheme mogen, maar niet vereist.

## 8. Werken per fase

- Voer per sessie **precies één fase** uit zoals opgegeven, tenzij expliciet anders
  gevraagd. Bouw geen features vooruit — dat maakt reviews en debugging moeilijker.
- Werk aan het einde van elke fase `PROGRESS.md` bij: welke bestanden zijn aangemaakt
  of gewijzigd, welke openstaande punten er zijn, en wat de volgende fase is.
- Commits: één per logische stap, beschrijvende Nederlandse of Engelse messages,
  bijvoorbeeld `fase 0: projectskelet + CI voor unsigned IPA`.
