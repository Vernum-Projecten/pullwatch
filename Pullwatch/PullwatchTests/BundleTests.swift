import AppKit
import Foundation
import PullwatchCore
import Testing

@testable import Pullwatch

/// Wat de gebouwde app moet zijn, los van de code: dezelfde bundle id, een menubalk-app,
/// alle vier de talen en een icoon. Vangt een fout in het Xcode-project of de xcconfig.
@Suite struct BundleTests {
    let info = Bundle.main.infoDictionary ?? [:]

    @Test func keepsTheBundleIdentifier() {
        // Instellingen, meldingstoestemming en Keychain-tokens hangen hieraan.
        #expect(Bundle.main.bundleIdentifier == "nl.torrisi.pullwatch")
    }

    @Test func runsFromTheMenuBar() {
        #expect(info["LSUIElement"] as? Bool == true)
    }

    @Test func shipsEveryLanguageTheAppOffers() {
        let offered = AppLanguage.allCases.filter { $0 != .system }.map(\.rawValue)
        #expect(Set(offered) == ["nl", "en", "de", "fr"])
        for code in offered {
            #expect(Bundle.main.localizations.contains(code), "geen \(code).lproj in de app")
            #expect((info["CFBundleLocalizations"] as? [String])?.contains(code) == true, "\(code) ontbreekt in CFBundleLocalizations")
        }
    }

    @Test @MainActor func hasAVersionFromTheXcconfig() throws {
        let version = try #require(info["CFBundleShortVersionString"] as? String)
        #expect(version.split(separator: ".").count == 3)
        #expect(version.allSatisfy { $0.isNumber || $0 == "." })
        #expect(Int(info["CFBundleVersion"] as? String ?? "") != nil)
        #expect(AppModel.currentVersion == version)
    }

    @Test func hasAnAppIcon() {
        #expect(info["CFBundleIconName"] as? String == "AppIcon")
        #expect(NSImage(named: "AppIcon") != nil)
    }
}
