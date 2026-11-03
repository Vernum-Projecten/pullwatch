import Foundation
import Testing

/// Elke tekst in de String Catalogs heeft alle vier de talen (nl, en, de, fr), zodat een nieuwe
/// tekst niet ongemerkt alleen in het Nederlands in de app komt.
@Suite struct LocalizationTests {
    static let languages = ["nl", "en", "de", "fr"]

    /// De catalogs naast deze map: die van de app en die van PullwatchCore.
    static let catalogs: [URL] = {
        let tests = URL(filePath: #filePath).deletingLastPathComponent()
        return [
            tests.appending(path: "../Pullwatch/Localizable.xcstrings"),
            tests.appending(path: "../../PullwatchKit/Sources/PullwatchCore/Localizable.xcstrings"),
        ].map(\.standardizedFileURL)
    }()

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
}
