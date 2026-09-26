# Daytr8-logo

Twee varianten, allebei gebouwd op dezelfde gestileerde "8" (kader 100 × 140,
twee gestapelde lussen met scherpe hoeken linksboven en rechtsonder):

| Bestand | Wat |
|---|---|
| `daytr8-wordmark.svg` | Woordmerk "Daytr8": "Daytr" in `--daytr8-text`, de "8" in `--daytr8-accent`. |
| `daytr8-icon.svg` | Alleen de "8" in `--daytr8-accent` (herkenbaar vanaf 16–24 px). |
| `favicon.svg`, `favicon.ico`, `favicon-16/32/48.png` | Favicons, statisch in de kleuren van het standaardthema (Donker). |
| `apple-touch-icon.png`, `icon-192.png`, `icon-512.png` | Web/home-screen-iconen, statisch. |

In de app is het logo `Daytr8LogoView` (`TradeJournal/Views/Components/`);
die leest `Theme.textPrimary` en `Theme.accent`, dus hij volgt een themawissel
direct. De SVG's gebruiken CSS-variabelen met de Donker-kleuren als terugval.

Het app-icoon (`AppIcon.appiconset/AppIcon-1024.png`), het launch-logo
(`LaunchLogo.imageset`) en de PNG's/ICO hierboven worden gemaakt met:

```sh
pip install pillow
python3 Branding/generate_icons.py
```
