import Foundation
import PullwatchCore

/// Een account zoals een agent het ziet: id, dienst, naam en host. Nooit de inlogmethode, het
/// token, een Keychain-item of de gebruiker van de CLI.
struct MCPAccountInfo: Encodable {
    let id: UUID
    /// "GitHub", "Azure DevOps", "GitLab" of "Gitea" (ook Forgejo en Codeberg; de host zegt welke).
    let service: String
    /// "@login" na inloggen met GitHub, anders de gevolgde eigenaren.
    let name: String
    /// De host van de dienst ("github.com", "gitlab.example.com", "dev.azure.com").
    let host: String

    init(_ account: Account) {
        id = account.id
        service = account.kind.name
        if let login = account.login, !login.isEmpty {
            name = "@\(login)"
        } else {
            let owners = account.owners.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            name = owners.isEmpty ? account.kind.name : owners.joined(separator: ", ")
        }
        // `host()` zonder gebruikersnaam of wachtwoord uit de URL.
        host = account.effectiveInstanceURL?.host() ?? "dev.azure.com"
    }

    static let fields: [String: MCPSchema] = [
        "id": .string("The account id; pass it as account_id when a repository name is followed by more than one account."),
        "service": .string("The service.", oneOf: ProviderKind.allCases.map(\.name)),
        "name": .string("The signed-in login (with @) or the followed owners."),
        "host": .string("The host of the service."),
    ]
}
