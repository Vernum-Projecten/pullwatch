import Foundation
import Testing

@testable import Pullwatch

/// De taalkeuze schrijft `AppleLanguages` in de eigen defaults; elke test heeft een eigen suite.
@MainActor @Suite struct AppLanguageTests {
    let suite = "nl.torrisi.pullwatch.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suite)!
    }

    private func languages() -> [String]? {
        defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String]
    }

    @Test func selectSystemRemovesOverride() {
        AppLanguage.select(.de, in: defaults)
        AppLanguage.select(.system, in: defaults)
        #expect(languages() == nil)
        #expect(AppLanguage.current(in: defaults, domain: suite) == .system)
    }

    @Test func selectEnglishStoresIt() {
        AppLanguage.select(.en, in: defaults)
        #expect(AppLanguage.current(in: defaults, domain: suite) == .en)
        #expect(languages() == ["en"])
    }

    @Test func unknownCodeIsSystem() {
        defaults.set(["pt"], forKey: "AppleLanguages")
        #expect(AppLanguage.current(in: defaults, domain: suite) == .system)
    }

    @Test func everyLanguageHasAName() {
        for language in AppLanguage.allCases {
            #expect(!language.name.isEmpty)
        }
    }
}
