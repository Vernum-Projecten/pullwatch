import Foundation

/// De dienst achter een account.
public enum ProviderKind: String, Codable, Hashable, Sendable, CaseIterable {
    // Een nieuwe dienst komt erbij als nieuwe case; de rawValue staat in config.json en
    // verandert nooit, zodat een bestaande config gewoon blijft decoderen.
    case azureDevOps, gitHub, gitLab

    /// Productnaam, in elke taal hetzelfde.
    public var name: String {
        switch self {
        case .azureDevOps: "Azure DevOps"
        case .gitHub: "GitHub"
        case .gitLab: "GitLab"
        }
    }

    /// Kan een account van deze dienst op een eigen server staan (`Account.instanceURL`)?
    /// GitLab self-managed, en GitHub Enterprise Server of GHE.com.
    var supportsInstanceURL: Bool { self == .gitLab || self == .gitHub }

    /// Het adres van de dienst zonder eigen server; Azure DevOps heeft er een per organisatie.
    public var defaultInstanceURL: URL? {
        switch self {
        case .azureDevOps: nil
        case .gitHub: URL(string: "https://github.com")
        case .gitLab: URL(string: "https://gitlab.com")
        }
    }
}

/// Hoe een account inlogt.
public enum AuthMethod: String, Codable, Hashable, Sendable, CaseIterable {
    /// Personal access token in de Keychain.
    case pat
    /// Het token van `az` of `gh`.
    case cli
    /// Inloggen met GitHub via de Pullwatch GitHub App (alleen GitHub); tokens in de Keychain.
    case gitHubApp
}
