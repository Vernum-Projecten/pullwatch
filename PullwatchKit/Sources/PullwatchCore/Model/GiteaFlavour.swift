public import Foundation

/// Welke dienst een account op de Gitea-API (`ProviderKind.gitea`) is: Codeberg (codeberg.org),
/// Forgejo (altijd een eigen server) of Gitea (gitea.com of een eigen server). De API is dezelfde;
/// de smaak bepaalt de naam, het logo en het adres zonder eigen server.
public enum GiteaFlavour: String, Codable, Hashable, Sendable, CaseIterable {
    // De rawValue staat in config.json en verandert nooit.
    case codeberg, forgejo, gitea

    /// Productnaam, in elke taal hetzelfde.
    public var name: String {
        switch self {
        case .codeberg: "Codeberg"
        case .forgejo: "Forgejo"
        case .gitea: "Gitea"
        }
    }

    /// Het adres zonder eigen server: codeberg.org en gitea.com. Forgejo heeft geen eigen dienst,
    /// dus daar is een server altijd nodig.
    public var defaultInstanceURL: URL? {
        switch self {
        case .codeberg: URL(string: "https://codeberg.org")
        case .forgejo: nil
        case .gitea: URL(string: "https://gitea.com")
        }
    }

    /// Kan het account op een eigen server staan? Codeberg is altijd codeberg.org.
    public var allowsOwnServer: Bool { self != .codeberg }
}
