import Foundation
import Testing
@testable import PullwatchCore

/// De tekst van PullwatchCore volgt de taal die de app koos.
@Suite struct CoreLocalizationTests {
    @Test func coreStringsFollowTheChosenLanguage() {
        #expect(String(localized: "Geen token ingesteld", bundle: .core(for: "de")) == "Kein Token festgelegt")
        #expect(String(localized: "Geen token ingesteld", bundle: .core(for: "en")) == "No token set")
        // Nederlands is de brontaal en heeft geen eigen lproj.
        #expect(String(localized: "Geen token ingesteld", bundle: .core(for: "nl")) == "Geen token ingesteld")
    }
}
