import Foundation

/// Laadt de broker-templates voor de screenshot-import uit
/// `Resources/ScreenshotTemplates/*.json` in de app-bundle.
///
/// Bestanden die geen geldig template zijn, of een nieuwer `formatVersion`
/// hebben dan deze app begrijpt, worden overgeslagen in plaats van de hele
/// import te laten falen.
public enum ScreenshotTemplateStore {

    /// Map in de bundle (folder reference in `project.yml`).
    public static let directoryName = "ScreenshotTemplates"

    /// Meegeleverde templates, één keer ingelezen.
    public static let bundled: [ScreenshotTemplate] = bundledTemplates()

    /// Leest alle templates uit `bundle`. Valt terug op JSON-bestanden in de
    /// root van de bundle, voor het geval de map platgeslagen is meegekopieerd.
    public static func bundledTemplates(in bundle: Bundle = Bundle(for: BundleToken.self)) -> [ScreenshotTemplate] {
        var urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: directoryName) ?? []
        if urls.isEmpty {
            urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        }
        return templates(from: urls)
    }

    /// Decodeert de bestanden en sorteert: platforms op naam, terugval als laatste.
    public static func templates(from urls: [URL]) -> [ScreenshotTemplate] {
        let decoded = urls.compactMap { url -> ScreenshotTemplate? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decode(data)
        }
        return decoded.sorted { lhs, rhs in
            if lhs.isFallbackTemplate != rhs.isFallbackTemplate { return !lhs.isFallbackTemplate }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public enum TemplateError: Error, Equatable {
        case unsupportedFormatVersion(Int)
    }

    /// Decodeert één template-JSON.
    public static func decode(_ data: Data) throws -> ScreenshotTemplate {
        let template = try JSONDecoder().decode(ScreenshotTemplate.self, from: data)
        guard template.formatVersion <= ScreenshotTemplate.supportedFormatVersion else {
            throw TemplateError.unsupportedFormatVersion(template.formatVersion)
        }
        return template
    }

    /// Anker om de app-bundle te vinden, ook vanuit de unit-test-target.
    public final class BundleToken {}
}
