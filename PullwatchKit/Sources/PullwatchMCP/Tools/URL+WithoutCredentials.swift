import Foundation
import PullwatchCore

extension URL {
    /// Dezelfde URL zonder gebruikersnaam en wachtwoord. Een eigen server kan in de instellingen
    /// met inloggegevens in de URL staan (`https://oauth2:<token>@gitlab.example.com`); die mogen
    /// nooit in de uitvoer van een tool komen.
    var withoutCredentials: URL {
        guard user(percentEncoded: true) != nil || password(percentEncoded: true) != nil,
              var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.user = nil
        components.password = nil
        return components.url ?? self
    }
}

extension Account {
    /// De webpagina van een repo, zonder inloggegevens (`Account.repoWebURL(_:)`).
    func safeRepoWebURL(_ repo: String) -> URL? {
        repoWebURL(repo)?.withoutCredentials
    }
}
