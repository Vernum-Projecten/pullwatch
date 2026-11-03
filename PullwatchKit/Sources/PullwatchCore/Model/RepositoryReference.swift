import Foundation

/// Waarom een zelf ingetypte of geplakte repository niet toe te voegen is, in gewone woorden.
public enum RepositoryProblem: Error, Equatable, Sendable {
    /// Geen `eigenaar/repo` en geen link die Pullwatch herkent.
    case unrecognised(ProviderKind)
    /// Een link naar een andere dienst dan die van het account.
    case otherService(ProviderKind)
    /// Een Azure DevOps-link naar een andere organisatie dan die van het account.
    case otherOrganization(found: String, expected: String)
    /// Staat al bij de losse repositories van dit account.
    case alreadyAdded(String)
    /// Deze dienst kan (nog) geen losse repositories toevoegen.
    case unsupported

    public var userMessage: String {
        switch self {
        case .unrecognised(.azureDevOps):
            return String(localized: "Typ project/repo, of plak de link van de repository.", bundle: .localizedCore)
        case .unrecognised:
            return String(localized: "Typ eigenaar/repo, of plak de link van de repository.", bundle: .localizedCore)
        case .otherService(let kind):
            return String(localized: "Dit is een link naar \(kind.name). Voeg hem toe bij een account van \(kind.name).", bundle: .localizedCore, comment: "Dienst, twee keer")
        case .otherOrganization(let found, let expected):
            return String(localized: "Deze repository staat in de organisatie \(found); dit account hoort bij \(expected).", bundle: .localizedCore, comment: "Organisatie van de link, organisatie van het account")
        case .alreadyAdded(let repo):
            return String(localized: "\(repo) staat al in de lijst.", bundle: .localizedCore, comment: "Repo")
        case .unsupported:
            return String(localized: "Bij deze dienst kun je nog geen losse repositories toevoegen.", bundle: .localizedCore)
        }
    }
}

/// Wat `PRProvider.checkRepository` vond: de naam zoals de dienst hem schrijft, en of de
/// repository alleen zonder inloggen te lezen is (een openbare repo waar het token niet bij mag).
public struct RepositoryCheck: Equatable, Sendable {
    public var name: String
    public var readWithoutSignIn: Bool

    public init(name: String, readWithoutSignIn: Bool = false) {
        self.name = name
        self.readWithoutSignIn = readWithoutSignIn
    }
}

/// Leest wat iemand in het veld "Andere repositories" typt of plakt: `eigenaar/repo` (GitHub),
/// `project/repo` (Azure DevOps), of een link van github.com of dev.azure.com. Geeft de repo in
/// de vorm van `Account.repoWatch`. Een nieuwe dienst (zoals GitLab) krijgt hier zijn eigen tak.
public enum RepositoryReference {
    public static func parse(_ input: String, kind: ProviderKind, organization: String) throws(RepositoryProblem) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix(".git") { text.removeLast(4) }

        if let link = link(text) {
            guard link.kind == kind else { throw .otherService(link.kind) }
            if kind == .azureDevOps, let found = link.organization,
               found.caseInsensitiveCompare(organization) != .orderedSame {
                throw .otherOrganization(found: found, expected: organization)
            }
            return try plain(link.repo, kind: kind)
        }
        if text.contains("://") || text.hasPrefix("git@") { throw .unrecognised(kind) }
        return try plain(text, kind: kind)
    }

    /// `a/b` met precies twee delen, met de tekens die de dienst toestaat.
    private static func plain(_ text: String, kind: ProviderKind) throws(RepositoryProblem) -> String {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else { throw .unrecognised(kind) }
        switch kind {
        case .gitHub:
            // GitHub: eigenaar letters, cijfers en streepjes; repo ook punt en underscore.
            let owner = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
            let repo = owner.union(CharacterSet(charactersIn: "._"))
            guard parts[0].unicodeScalars.allSatisfy(owner.contains), parts[0].count <= 39,
                  parts[1].unicodeScalars.allSatisfy(repo.contains), parts[1] != ".", parts[1] != ".." else {
                throw .unrecognised(kind)
            }
        case .azureDevOps:
            // Azure DevOps staat spaties toe; een deel dat met "_" begint is een pagina (`_git`).
            guard parts.allSatisfy({ !$0.hasPrefix("_") && $0.trimmingCharacters(in: .whitespaces) == $0 }) else {
                throw .unrecognised(kind)
            }
        }
        return parts.joined(separator: "/")
    }

    /// Een link van een bekende dienst, met de repo erin en (Azure DevOps) de organisatie.
    private static func link(_ text: String) -> (kind: ProviderKind, repo: String, organization: String?)? {
        var text = text
        // SSH: git@github.com:eigenaar/repo, git@ssh.dev.azure.com:v3/org/project/repo
        if text.hasPrefix("git@"), let colon = text.firstIndex(of: ":") {
            let host = text[text.index(text.startIndex, offsetBy: 4)..<colon]
            text = "ssh://\(host)/\(text[text.index(after: colon)...])"
        } else if !text.contains("://"), let first = text.split(separator: "/").first, first.contains(".") {
            text = "https://" + text // "github.com/eigenaar/repo" zonder schema
        }
        guard let url = URL(string: text) ?? URL(string: text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""),
              let host = url.host()?.lowercased() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "github.com", "www.github.com":
            guard path.count >= 2 else { return (.gitHub, "", nil) }
            return (.gitHub, "\(path[0])/\(path[1])", nil)
        case "dev.azure.com":
            // https://dev.azure.com/org/project/_git/repo[/…]
            guard path.count >= 4, path[2] == "_git" else { return (.azureDevOps, "", path.first) }
            return (.azureDevOps, "\(path[1])/\(path[3])", path[0])
        case "ssh.dev.azure.com":
            // ssh://ssh.dev.azure.com/v3/org/project/repo
            guard path.count >= 4, path[0] == "v3" else { return (.azureDevOps, "", nil) }
            return (.azureDevOps, "\(path[2])/\(path[3])", path[1])
        default:
            // https://org.visualstudio.com/[DefaultCollection/]project/_git/repo
            guard host.hasSuffix(".visualstudio.com") else { return nil }
            let organization = String(host.dropLast(".visualstudio.com".count))
            let rest = path.first?.caseInsensitiveCompare("DefaultCollection") == .orderedSame ? Array(path.dropFirst()) : path
            guard rest.count >= 3, rest[1] == "_git" else { return (.azureDevOps, "", organization) }
            return (.azureDevOps, "\(rest[0])/\(rest[2])", organization)
        }
    }
}
