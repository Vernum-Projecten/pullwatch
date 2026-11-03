import Foundation
import Testing

/// Elke tekst in de String Catalogs heeft alle vier de talen (nl, en, de, fr), zodat een nieuwe
/// tekst niet ongemerkt alleen in het Nederlands in de app komt.
@Suite struct LocalizationTests {
    static let languages = ["nl", "en", "de", "fr"]

    /// De catalogs naast deze map: die van de app en die van elke PullwatchKit-module met teksten.
    static let catalogs: [URL] = {
        let tests = URL(filePath: #filePath).deletingLastPathComponent()
        return [
            tests.appending(path: "../Pullwatch/Localizable.xcstrings"),
            tests.appending(path: "../../PullwatchKit/Sources/PullwatchCore/Localizable.xcstrings"),
            tests.appending(path: "../../PullwatchKit/Sources/PullwatchGitHub/Localizable.xcstrings"),
        ].map(\.standardizedFileURL)
    }()

    /// Een nieuwe module met een eigen catalog hoort in `catalogs`, anders controleert niemand hem.
    @Test func everyKitCatalogIsChecked() throws {
        let sources = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../PullwatchKit/Sources").standardizedFileURL
        let modules = try FileManager.default.contentsOfDirectory(atPath: sources.path(percentEncoded: false))
        let found = modules
            .map { sources.appending(path: "\($0)/Localizable.xcstrings").standardizedFileURL }
            .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
        #expect(!found.isEmpty)
        #expect(Set(found).isSubset(of: Set(Self.catalogs)), "Ontbreekt in catalogs: \(Set(found).subtracting(Self.catalogs).map(\.path))")
    }

    struct Catalog: Decodable {
        struct Entry: Decodable {
            let shouldTranslate: Bool?
            let localizations: [String: Localization]?
        }
        struct Localization: Decodable {
            struct Unit: Decodable { let state: String?; let value: String? }
            /// Een deel van de tekst met eigen meervoudsvormen (`%#@naam@`), bij meer dan één argument.
            struct Substitution: Decodable {
                let variations: [String: [String: Localization]]?
            }
            let stringUnit: Unit?
            let variations: [String: [String: Localization]]?
            let substitutions: [String: Substitution]?
        }
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    @Test(arguments: catalogs)
    func everyStringHasEveryLanguage(_ url: URL) throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        #expect(!catalog.strings.isEmpty)
        var missing: [String] = []
        for (key, entry) in catalog.strings where entry.shouldTranslate != false && !key.isEmpty {
            for language in Self.languages where language != catalog.sourceLanguage {
                guard let localization = entry.localizations?[language] else {
                    missing.append("\(language): \(key)")
                    continue
                }
                if localization.stringUnit?.state == "new" || localization.stringUnit?.value?.isEmpty == true {
                    missing.append("\(language) (leeg): \(key)")
                }
            }
        }
        #expect(missing.isEmpty, "\(url.lastPathComponent) mist vertalingen:\n\(missing.sorted().joined(separator: "\n"))")
    }

    /// Een tekst met een aantal en meervoudsvormen heeft in elke taal minstens `one` en `other`,
    /// ook in het Nederlands: anders staat er "1 nieuwe PR's" of valt een taal terug op de sleutel.
    /// Dat geldt voor de hele tekst en voor elke substitutie (`%#@naam@`) met meervoudsvormen.
    @Test(arguments: catalogs)
    func everyPluralHasOneAndOther(_ url: URL) throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        var missing: [String] = []
        for (key, entry) in catalog.strings {
            let localizations = entry.localizations ?? [:]
            // nil = de hele tekst, anders de naam van de substitutie.
            var plurals: Set<String?> = []
            for localization in localizations.values {
                if localization.variations?["plural"] != nil { plurals.insert(nil) }
                for (name, substitution) in localization.substitutions ?? [:] where substitution.variations?["plural"] != nil {
                    plurals.insert(name)
                }
            }
            for plural in plurals {
                for language in Self.languages {
                    let localization = localizations[language]
                    let variations = plural.map { localization?.substitutions?[$0]?.variations } ?? localization?.variations
                    let forms = Set(variations?["plural"]?.keys.map { $0 } ?? [])
                    let absent = ["one", "other"].filter { !forms.contains($0) }
                    if !absent.isEmpty {
                        let place = plural.map { "\(key) (%#@\($0)@)" } ?? key
                        missing.append("\(language) \(absent.joined(separator: ", ")): \(place)")
                    }
                }
            }
        }
        #expect(missing.isEmpty, "\(url.lastPathComponent) mist meervoudsvormen:\n\(missing.sorted().joined(separator: "\n"))")
    }
}
