import Foundation

/// Kleur in HSB (hue, saturation, brightness; alle waardes 0…1). Wordt
/// gebruikt door het kleurenwiel van de thema-editor en de paletgenerator.
struct HSBColor: Equatable, Hashable, Sendable {

    var hue: Double
    var saturation: Double
    var brightness: Double

    init(hue: Double, saturation: Double, brightness: Double) {
        let wrapped = hue.truncatingRemainder(dividingBy: 1)
        self.hue = wrapped < 0 ? wrapped + 1 : wrapped
        self.saturation = min(max(saturation, 0), 1)
        self.brightness = min(max(brightness, 0), 1)
    }

    init(_ color: HexColor) {
        let r = color.red, g = color.green, b = color.blue
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let delta = maxValue - minValue

        var hue = 0.0
        if delta > 0 {
            if maxValue == r {
                hue = (g - b) / delta
            } else if maxValue == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
        }
        self.init(
            hue: hue,
            saturation: maxValue == 0 ? 0 : delta / maxValue,
            brightness: maxValue
        )
    }

    /// De kleur als (op 8 bit afgeronde) hex-waarde.
    var hexColor: HexColor {
        let sector = hue * 6
        let chroma = brightness * saturation
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - chroma

        let rgb: (Double, Double, Double)
        switch Int(sector) {
        case 0: rgb = (chroma, x, 0)
        case 1: rgb = (x, chroma, 0)
        case 2: rgb = (0, chroma, x)
        case 3: rgb = (0, x, chroma)
        case 4: rgb = (x, 0, chroma)
        default: rgb = (chroma, 0, x)
        }
        return HexColor(red: rgb.0 + m, green: rgb.1 + m, blue: rgb.2 + m)
    }
}

extension HexColor {

    static let white = HexColor("#FFFFFF")
    static let black = HexColor("#000000")

    /// Kleur uit RGB-kanalen (0…1), afgerond op 8 bit per kanaal.
    init(red: Double, green: Double, blue: Double) {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        self.init(String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue)))
    }

    /// `true` voor "#RRGGBB" of "RRGGBB" (hoofdletterongevoelig).
    static func isValidHex(_ string: String) -> Bool {
        var sanitized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        return sanitized.count == 6 && sanitized.allSatisfy(\.isHexDigit)
    }

    /// Lineaire menging: `amount` 0 = deze kleur, 1 = `other`.
    func mixed(with other: HexColor, amount: Double) -> HexColor {
        let t = min(max(amount, 0), 1)
        return HexColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }

    /// Laagste contrastverhouding van deze kleur op de gegeven oppervlakken.
    func minimumContrast(on surfaces: [HexColor]) -> Double {
        surfaces.map { HexColor.contrastRatio(self, $0) }.min() ?? 21
    }

    /// Deze kleur, zo min mogelijk lichter of donkerder gemaakt tot hij op
    /// alle `surfaces` minimaal `minimum`:1 contrast haalt. Lukt dat niet,
    /// dan de variant met het hoogst haalbare contrast.
    func ensuringContrast(on surfaces: [HexColor], minimum: Double) -> HexColor {
        guard minimumContrast(on: surfaces) < minimum else { return self }

        // Eerst de richting die het meeste contrast kan opleveren.
        let towardsWhite = HexColor.white.minimumContrast(on: surfaces) >= HexColor.black.minimumContrast(on: surfaces)
        let directions: [HexColor] = towardsWhite ? [.white, .black] : [.black, .white]

        var best = self
        var bestRatio = minimumContrast(on: surfaces)
        for target in directions {
            for step in 1...40 {
                let candidate = mixed(with: target, amount: Double(step) / 40)
                let ratio = candidate.minimumContrast(on: surfaces)
                if ratio >= minimum { return candidate }
                if ratio > bestRatio {
                    best = candidate
                    bestRatio = ratio
                }
            }
        }
        return best
    }

    /// Wit of bijna-zwart, afhankelijk van wat het beste leest op deze kleur.
    var readableForeground: HexColor {
        let dark = HexColor("#0B1220")
        return HexColor.contrastRatio(.white, self) >= HexColor.contrastRatio(dark, self) ? .white : dark
    }
}
