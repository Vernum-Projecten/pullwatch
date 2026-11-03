import AppKit
import Foundation
import PullwatchCore
import Testing

@testable import Pullwatch

/// Wat de gebouwde app moet zijn, los van de code: dezelfde bundle id, een menubalk-app,
/// alle vier de talen en een icoon. Vangt een fout in het Xcode-project of de xcconfig.
/// Op de main actor, zoals de typen van de app (`AppModel.currentVersion`).
@MainActor @Suite struct BundleTests {
    let info = Bundle.main.infoDictionary ?? [:]

    @Test func keepsTheBundleIdentifier() {
        // Instellingen, meldingstoestemming en Keychain-tokens hangen hieraan.
        #expect(Bundle.main.bundleIdentifier == "nl.torrisi.pullwatch")
    }

    @Test func runsFromTheMenuBar() {
        #expect(info["LSUIElement"] as? Bool == true)
    }

    /// De talen staan in de bundle, zodat macOS ze aanbiedt onder Systeeminstellingen → Algemeen →
    /// Taal en regio → Apps (en in Instellingen van Pullwatch zelf).
    @Test func shipsEveryLanguageTheAppOffers() {
        for code in ["nl", "en", "de", "fr"] {
            #expect(Bundle.main.localizations.contains(code), "geen \(code).lproj in de app")
            #expect((info["CFBundleLocalizations"] as? [String])?.contains(code) == true, "\(code) ontbreekt in CFBundleLocalizations")
        }
    }

    @Test func hasAVersionFromTheXcconfig() throws {
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
