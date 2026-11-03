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
            let stringUnit: Unit?
            let variations: [String: [String: Localization]]?
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
    @Test(arguments: catalogs)
    func everyPluralHasOneAndOther(_ url: URL) throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        var missing: [String] = []
        for (key, entry) in catalog.strings {
            let localizations = entry.localizations ?? [:]
            guard localizations.values.contains(where: { $0.variations?["plural"] != nil }) else { continue }
            for language in Self.languages {
                let forms = Set(localizations[language]?.variations?["plural"]?.keys.map { $0 } ?? [])
                let absent = ["one", "other"].filter { !forms.contains($0) }
                if !absent.isEmpty { missing.append("\(language) \(absent.joined(separator: ", ")): \(key)") }
            }
        }
        #expect(missing.isEmpty, "\(url.lastPathComponent) mist meervoudsvormen:\n\(missing.sorted().joined(separator: "\n"))")
    }
}
