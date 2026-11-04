public import Foundation

/// De dienst achter een account.
public enum ProviderKind: String, Codable, Hashable, Sendable, CaseIterable {
    // Een nieuwe dienst komt erbij als nieuwe case; de rawValue staat in config.json en
    // verandert nooit, zodat een bestaande config gewoon blijft decoderen.
    case azureDevOps, gitHub, gitLab, bitbucket
    /// Gitea, Forgejo en Codeberg: één API (`/api/v1`); welke van de drie staat in
    /// `Account.giteaFlavour`.
    case gitea

    /// Productnaam, in elke taal hetzelfde.
    public var name: String {
        switch self {
        case .azureDevOps: "Azure DevOps"
        case .gitHub: "GitHub"
        case .gitLab: "GitLab"
        case .bitbucket: "Bitbucket"
        case .gitea: "Gitea"
        }
    }

    /// Het teken voor het nummer van een pull request, zoals de dienst het zelf schrijft: `#1570` op
    /// GitHub en Bitbucket (`workspace/repo#12`), `!42` bij een merge request van GitLab en een pull
    /// request van Azure DevOps, `#12` op Gitea, Forgejo en Codeberg (`owner/repo#12`). Bewust
    /// zonder `default`: een nieuwe dienst kiest hier zelf.
    public var pullRequestPrefix: String {
        switch self {
        case .azureDevOps: "!"
        case .gitHub: "#"
        case .gitLab: "!"
        case .bitbucket: "#"
        case .gitea: "#"
        }
    }

    /// Kan een account van deze dienst op een eigen server staan (`Account.instanceURL`)?
    /// GitLab self-managed, GitHub Enterprise Server of GHE.com, en een eigen Gitea- of
    /// Forgejo-server.
    var supportsInstanceURL: Bool { self == .gitLab || self == .gitHub || self == .gitea }

    /// Het adres van de dienst zonder eigen server; Azure DevOps heeft er een per organisatie, en
    /// bij Gitea hangt het af van de smaak (`Account.defaultInstanceURL`).
    public var defaultInstanceURL: URL? {
        switch self {
        case .azureDevOps: nil
        case .gitHub: URL(string: "https://github.com")
        case .gitLab: URL(string: "https://gitlab.com")
        case .bitbucket: URL(string: "https://bitbucket.org")
        case .gitea: nil
        }
    }
}

/// Hoe een account inlogt.
public enum AuthMethod: String, Codable, Hashable, Sendable, CaseIterable {
    /// Personal access token in de Keychain; bij Bitbucket een API-token met scopes (met het
    /// e-mailadres van het Atlassian-account in `Account.email`).
    case pat
    /// Het token van `az` of `gh`.
    case cli
    /// Inloggen met GitHub via de Pullwatch GitHub App (alleen GitHub); tokens in de Keychain.
    case gitHubApp
}
