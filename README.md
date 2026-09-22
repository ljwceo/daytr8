# TradeJournal

Native iOS day-trading journal in Swift/SwiftUI. Volledig offline, geen accounts,
geen backend, geen betaalde developer-entitlements nodig. De app wordt **unsigned**
gebouwd via GitHub Actions en gesignd/gesideload via [Signulous](https://signulous.com/).

Status: **fase 2** — SwiftData-datamodel met statistieken en seed-data (fase 1),
en een werkend trade log met tradedetail en een slim tradeformulier (fase 2).
Dashboard, Kalender en Rapporten zijn nog placeholders. Zie [`SPEC.md`](SPEC.md)
voor de volledige productscope en [`PROGRESS.md`](PROGRESS.md) voor de
voortgang per fase.

## Technische basis

- Swift 5.10+, SwiftUI, iOS 17.0+
- SwiftData (offline opslag, komt vanaf fase 1)
- Swift Charts (dashboard/rapporten, komt vanaf latere fases)
- MVVM-architectuur — zie [`CLAUDE.md`](CLAUDE.md) voor conventies
- Projectbestand wordt gegenereerd met [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  op basis van [`project.yml`](project.yml). Het `.xcodeproj` staat **niet** in de repo.
- Bundle identifier: `com.tradejournal.app` (aanpasbaar in `project.yml`).

### Geen speciale entitlements

Zodat de app zonder betaald Apple Developer Program via Signulous ondertekend kan
worden, gebruikt TradeJournal expliciet **geen** iCloud/CloudKit, push notifications,
App Groups of Sign in with Apple. Lokale notificaties (`UNUserNotificationCenter`),
Face ID (`LocalAuthentication`), fotobibliotheek en camera worden wel gebruikt
en zijn met usage descriptions in `Info.plist` opgenomen.

## Lokaal bouwen (optioneel, alleen op een Mac)

```bash
brew install xcodegen
xcodegen generate
open TradeJournal.xcodeproj
```

Kies in Xcode het `TradeJournal`-scheme en druk op ▶︎. Voor een unsigned Release-build
op de commandline:

```bash
xcodebuild \
  -project TradeJournal.xcodeproj \
  -scheme TradeJournal \
  -sdk iphoneos \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build
```

## Installeren op je iPhone via Signulous

Je hoeft geen Mac te hebben. Alles gebeurt via GitHub en de Signulous-app op je iPhone.

### 1. Bouw de `.ipa` in GitHub Actions

1. Fork/kloon deze repo en push naar `main` (of trigger de workflow handmatig via
   **Actions → Build unsigned IPA → Run workflow**). Voor een release: push een tag
   die begint met `v`, bijvoorbeeld `v0.1.0`.
2. Wacht tot de workflow **Build unsigned IPA** groen is. De job draait op
   `macos-15`, installeert XcodeGen, genereert het project, bouwt Release voor
   `iphoneos` zonder code signing en zipt het resultaat als `TradeJournal.ipa`.
3. Open de succesvolle run en download het artifact
   **`TradeJournal-unsigned-ipa`** onderaan de pagina. Pak de zip uit — daarin zit
   `TradeJournal.ipa`. (Bij een tag `v*` is de `.ipa` ook direct te vinden onder
   **Releases**.)

### 2. Sign en installeer via Signulous

1. Installeer de Signulous-app op je iPhone en registreer je Apple ID
   (of UDID-profiel) volgens de instructies op signulous.com.
2. Zet `TradeJournal.ipa` op een plek die je iPhone kan bereiken: iCloud Drive,
   Dropbox, een directe link, of AirDrop naar de Bestanden-app.
3. Open Signulous op je iPhone, kies **Sign IPA** (of "Upload IPA"), selecteer
   `TradeJournal.ipa` uit Bestanden en laat Signulous de app met jouw
   certificaat/provisioning profile signen.
4. Signulous biedt na het signen een installatielink of directe install-knop aan.
   Bevestig de installatie in iOS.
5. Ga naar **Instellingen → Algemeen → VPN en apparaatbeheer**, vertrouw het
   ontwikkelaars-/enterprise-profiel dat Signulous gebruikt, en open TradeJournal.

### 3. Vernieuwen wanneer je certificaat verloopt

Signulous-certificaten verlopen periodiek (afhankelijk van je Apple ID / plan).
Herhaal dan stap 2: opnieuw signen met dezelfde `.ipa` (of een nieuwere versie) en
opnieuw installeren. Vanaf fase 5 heeft TradeJournal ingebouwde backup/restore
naar de Bestanden-app, zodat je lokale data niet verloren gaat bij een
her-installatie.

### 4. Backup, restore en CSV-import

Alles staat onder **Meer → Data**:

- **Backup & herstel → Backup maken** maakt een `.zip` (`backup.json` + alle
  screenshots) en opent de share sheet. Kies *Bewaar in Bestanden* (bijv. iCloud
  Drive) of AirDrop hem naar je computer. Het dashboard toont een waarschuwing
  zodra je laatste backup ouder is dan 7 dagen.
- **Automatische backup**: kies een map in Bestanden en stel *dagelijks* of *bij
  elke app-start* in. De laatste 10 automatische backups blijven bewaard.
- **Herstel uit backup…** leest een backup-zip in, toont een samenvatting en
  vervangt na bevestiging alle data in de app. Doe dit direct na een
  her-installatie.
- **CSV importeren** herkent automatisch exports van Tradovate (Performance en
  Orders), NinjaTrader (Trades en Executions), TopstepX/ProjectX, MetaTrader 4/5
  en TradingView. Andere bestanden koppel je zelf per kolom. Losse fills worden
  samengevoegd tot trades en trades die al in je journal staan worden als
  duplicaat overgeslagen.
- **Trades exporteren als CSV** levert één rij per trade op; dit bestand kan
  ook weer geïmporteerd worden.

## Repostructuur

```
.
├── SPEC.md                      # Productspecificatie (alle fases)
├── PROGRESS.md                  # Voortgang per fase
├── CLAUDE.md                    # Architectuur- en code-afspraken
├── README.md
├── project.yml                  # XcodeGen-projectdefinitie
├── .github/workflows/
│   └── build-ipa.yml            # CI: unsigned IPA
└── TradeJournal/
    ├── App/                     # @main entry point
    ├── Models/                  # SwiftData-modellen (fase 1+)
    ├── Views/                   # SwiftUI-schermen per feature
    │   ├── Dashboard/
    │   ├── Calendar/
    │   ├── Trades/
    │   ├── Reports/
    │   └── More/
    ├── ViewModels/              # MVVM-viewmodels (fase 1+)
    ├── Services/                # SwiftData store, CSV, backup, notificaties (fase 1+)
    ├── Utilities/               # Theme, formatters, helpers
    └── Resources/               # Info.plist, Assets.xcassets
```
