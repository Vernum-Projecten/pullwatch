import Foundation
import PullwatchCore

/// Waarom de packages van een GitHub-account niet te lezen zijn: de reden van
/// `PublishedPackages.needsPermission`, in de taal van de app, met de precieze opdracht. `host` is
/// de host voor `gh` (`GitHubEndpoints.cliHost`): github.com, of de GitHub Enterprise-server.
enum GitHubPackagesReason {
    /// Een persoonlijk token of de GitHub CLI als manier van inloggen, zonder `read:packages`.
    static var tokenMissesScope: String {
        String(
            localized: "GitHub Packages is alleen te lezen met de scope read:packages: gebruik de GitHub CLI (gh auth refresh -s read:packages) of een persoonlijk token (classic) met read:packages.",
            bundle: .localizedGitHub,
            comment: "Reden waarom de packages van een GitHub-account met de GitHub CLI of een token niet te lezen zijn; read:packages en de gh-opdracht niet vertalen"
        )
    }

    /// GitHub App: Packages lezen met de GitHub CLI staat uit voor dit account.
    static var cliTurnedOff: String {
        String(
            localized: "Zet Packages lezen met de GitHub CLI aan voor dit account (Instellingen, Accounts): GitHub geeft packages niet aan de GitHub App.",
            bundle: .localizedGitHub,
            comment: "Reden waarom de packages van een GitHub App-account niet gelezen worden; Packages lezen met de GitHub CLI is de naam van de schakelaar in de account-editor"
        )
    }

    /// GitHub App: `gh` is niet geïnstalleerd.
    static func cliMissing(host: String) -> String {
        String(
            localized: "Installeer de GitHub CLI (brew install gh) en log in met gh auth login -h \(host) -s read:packages: GitHub geeft packages niet aan de GitHub App, Pullwatch leest ze met gh.",
            bundle: .localizedGitHub,
            comment: "Reden waarom de packages van een GitHub App-account niet te lezen zijn; de host van GitHub; de opdrachten niet vertalen"
        )
    }

    /// GitHub App: `gh` is er, maar niet ingelogd op de host van het account.
    static func cliLoggedOut(host: String) -> String {
        String(
            localized: "Log in met de GitHub CLI: gh auth login -h \(host) -s read:packages. GitHub geeft packages niet aan de GitHub App, Pullwatch leest ze met gh.",
            bundle: .localizedGitHub,
            comment: "Reden waarom de packages van een GitHub App-account niet te lezen zijn; de host van GitHub; de opdracht niet vertalen"
        )
    }

    /// GitHub App: het token van `gh` mist `read:packages`.
    static func cliMissesScope(host: String) -> String {
        String(
            localized: "Voer gh auth refresh -h \(host) -s read:packages uit: de GitHub CLI mist de scope read:packages.",
            bundle: .localizedGitHub,
            comment: "Reden waarom de packages van een GitHub App-account niet te lezen zijn; de host van GitHub; de opdracht en read:packages niet vertalen"
        )
    }

    /// GitHub App: `gh` heeft `read:packages`, maar zijn gebruiker mag geen van de eigenaren zien.
    static func cliNoAccess(host: String) -> String {
        String(
            localized: "De gebruiker van de GitHub CLI mag de packages van deze eigenaren niet lezen: log in met gh auth login -h \(host) als iemand die er wel bij kan.",
            bundle: .localizedGitHub,
            comment: "Reden waarom de packages van een GitHub App-account niet te lezen zijn; de host van GitHub; de opdracht niet vertalen"
        )
    }
}
