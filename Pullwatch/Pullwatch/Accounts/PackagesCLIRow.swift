import PullwatchGitHub
import SwiftUI

/// De schakelaar Packages lezen met de GitHub CLI van een GitHub App-account (#206), met wie `gh`
/// daarvoor gebruikt. GitHubs Packages-API weigert elk token van een GitHub App, dus de packages
/// komen met het token van `gh` voor de host van het account. Leest geen model uit de environment:
/// de editor geeft de waarden mee.
struct PackagesCLIRow: View {
    @Binding var isOn: Bool
    /// Hoe `gh` er op de host voor staat; nil zolang dat nog niet bekend is.
    let status: GhCLIStatus?
    /// Wie er met de GitHub App inlogde.
    let login: String?
    /// De host voor `gh` (github.com of de GitHub Enterprise-server).
    let host: String

    var body: some View {
        Toggle(isOn: $isOn) {
            Text("Packages lezen met de GitHub CLI")
            PackagesCLIStatusText(status: status, login: login, host: host)
        }
        .accessibilityIdentifier("account.packagesViaCLI")
        .help("GitHub geeft packages niet aan de GitHub App; Pullwatch leest ze met het token van gh, met de scope read:packages.")
    }
}

/// De regel onder de schakelaar: welk `gh`-account de packages leest, of wat er ontbreekt.
private struct PackagesCLIStatusText: View {
    let status: GhCLIStatus?
    let login: String?
    let host: String

    var body: some View {
        switch status {
        case nil:
            Text("GitHub geeft packages niet aan de GitHub App; Pullwatch leest ze met gh.")
        case .notInstalled:
            Text("De GitHub CLI is niet geïnstalleerd: installeer hem (brew install gh) en log in met gh auth login -h \(host) -s read:packages.", comment: "De host van GitHub; de opdrachten niet vertalen")
        case .notLoggedIn:
            Text("gh is niet ingelogd op \(host): log in met gh auth login -h \(host) -s read:packages.", comment: "De host van GitHub, twee keer; de opdracht niet vertalen")
        case .loggedIn(let user) where login == nil || user.caseInsensitiveCompare(login ?? "") == .orderedSame:
            Text("Leest met gh als \(user).", comment: "Het gh-account dat de packages leest")
        case .loggedIn(let user):
            Text("Leest met gh als \(user), niet als \(login ?? ""): dat werkt als \(user) de packages van de gevolgde eigenaren mag zien.", comment: "Het gh-account, het account van de GitHub App, nog eens het gh-account")
        }
    }
}
