import Foundation
import PullwatchCore

/// De adressen achter het menu Help: de website (één basis) en de repository op GitHub.
enum HelpLinks {
    /// De website met de documentatie (`site/`).
    static let website = URL(string: "https://pullwatch.net/")!
    /// De repository van Pullwatch, met de releases en de issues.
    static let repository = URL(string: "https://github.com/\(UpdateChecker.defaultOwner)/pullwatch/")!

    static var documentation: URL { website }
    /// De pagina uit `site/src/content/docs/using/keyboard-shortcuts.md`.
    static var keyboardShortcuts: URL { website.appending(path: "using/keyboard-shortcuts/") }
    static var newIssue: URL { repository.appending(path: "issues/new") }

    /// De release notes van deze versie.
    static func releaseNotes(version: String) -> URL {
        repository.appending(path: "releases/tag/v\(version)")
    }
}
