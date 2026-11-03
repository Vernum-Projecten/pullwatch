import Foundation
import Testing
@testable import PullwatchGitHub

/// De inlogteksten staan in de String Catalog van PullwatchGitHub, niet meer in die van PullwatchCore.
@Suite struct GitHubLocalizationTests {
    @Test func signInStringsFollowTheChosenLanguage() {
        #expect(String(localized: "Log opnieuw in bij GitHub.", bundle: .gitHub(for: "de")) == "Melde dich erneut bei GitHub an.")
        #expect(String(localized: "Log opnieuw in bij GitHub.", bundle: .gitHub(for: "en")) == "Sign in to GitHub again.")
        #expect(String(localized: "Log opnieuw in bij GitHub.", bundle: .gitHub(for: "fr")) == "Reconnectez-vous à GitHub.")
        // Nederlands is de brontaal en heeft geen eigen lproj.
        #expect(String(localized: "Log opnieuw in bij GitHub.", bundle: .gitHub(for: "nl")) == "Log opnieuw in bij GitHub.")
    }
}
