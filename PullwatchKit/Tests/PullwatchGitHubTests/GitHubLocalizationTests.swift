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

    @Test(arguments: [
        ("nl", "GraphQL-antwoord zonder gegevens"),
        ("en", "GraphQL response without data"),
        ("de", "GraphQL-Antwort ohne Daten"),
        ("fr", "Réponse GraphQL sans données"),
    ])
    func `A GraphQL answer without data is translated`(language: String, expected: String) {
        #expect(String(localized: "GraphQL-antwoord zonder gegevens", bundle: .gitHub(for: language)) == expected)
    }

    @Test(arguments: [
        ("nl", "GraphQL-antwoord zonder co-auteurs en checks"),
        ("en", "GraphQL response without co-authors and checks"),
        ("de", "GraphQL-Antwort ohne Co-Autoren und Checks"),
        ("fr", "Réponse GraphQL sans co-auteurs ni checks"),
    ])
    func `A GraphQL answer without co-authors and checks is translated`(language: String, expected: String) {
        #expect(String(localized: "GraphQL-antwoord zonder co-auteurs en checks", bundle: .gitHub(for: language)) == expected)
    }
}
