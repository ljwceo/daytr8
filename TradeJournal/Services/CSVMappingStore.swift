import Foundation

/// Onthoudt handmatige kolomkoppelingen van de CSV-import per kopregel, zodat
/// een bestand met dezelfde kolommen de volgende keer (ook na een herstart of
/// update) meteen goed gekoppeld is. Opgeslagen als JSON-tekst in
/// `UserDefaults`; `defaults` is injecteerbaar voor tests.
public final class CSVMappingStore {

    public static let key = "csvImport.savedMappings"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Sleutel voor een kopregel: kolomnamen genormaliseerd, in volgorde.
    public static func signature(for headers: [String]) -> String {
        headers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.joined(separator: "\u{1F}")
    }

    public func mapping(for headers: [String]) -> CSVColumnMapping? {
        all()[Self.signature(for: headers)]
    }

    public func save(_ mapping: CSVColumnMapping, for headers: [String]) {
        var mappings = all()
        mappings[Self.signature(for: headers)] = mapping
        guard let data = try? JSONEncoder().encode(mappings), let text = String(data: data, encoding: .utf8) else { return }
        defaults.set(text, forKey: Self.key)
    }

    private func all() -> [String: CSVColumnMapping] {
        guard let text = defaults.string(forKey: Self.key), let data = text.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: CSVColumnMapping].self, from: data)) ?? [:]
    }
}
