import Foundation

/// Waarom een zelf ingetypte of geplakte repository niet toe te voegen is, in gewone woorden.
public enum RepositoryProblem: Error, Equatable, Sendable {
    /// Geen `eigenaar/repo` en geen link die Pullwatch herkent.
    case unrecognised(ProviderKind)
    /// Een link naar een andere dienst dan die van het account.
    case otherService(ProviderKind)
    /// Een Azure DevOps-link naar een andere organisatie dan die van het account.
    case otherOrganization(found: String, expected: String)
    /// Een GitLab-link naar een andere server dan die van het account (host van de link, host van
    /// het account).
    case otherServer(found: String, expected: String)
    /// Staat al bij de losse repositories van dit account.
    case alreadyAdded(String)
    /// Deze dienst kan (nog) geen losse repositories toevoegen.
    case unsupported

    public var userMessage: String {
        switch self {
        case .unrecognised(.azureDevOps):
            return String(localized: "Typ project/repo, of plak de link van de repository.", bundle: .localizedCore)
        case .unrecognised(.gitLab):
            return String(localized: "Typ groep/project (ook met subgroepen), of plak de link van het project.", bundle: .localizedCore)
        case .unrecognised:
            return String(localized: "Typ eigenaar/repo, of plak de link van de repository.", bundle: .localizedCore)
        case .otherService(let kind):
            return String(localized: "Dit is een link naar \(kind.name). Voeg hem toe bij een account van \(kind.name).", bundle: .localizedCore, comment: "Dienst, twee keer")
        case .otherOrganization(let found, let expected):
            return String(localized: "Deze repository staat in de organisatie \(found); dit account hoort bij \(expected).", bundle: .localizedCore, comment: "Organisatie van de link, organisatie van het account")
        case .otherServer(let found, let expected):
            return String(localized: "Dit project staat op \(found); dit account hoort bij \(expected). Voeg het toe bij een account van die server.", bundle: .localizedCore, comment: "Host van de link, host van het account (bv. gitlab.com)")
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

extension ProviderKind {
    /// Kan een account van deze dienst losse repo's toevoegen (`Account.extraRepos`)? Elke dienst
    /// die Pullwatch nu kent kan het; een nieuwe pas als zijn provider `checkRepository` heeft.
    public var supportsExtraRepos: Bool {
        switch self {
        case .gitHub, .azureDevOps, .gitLab: true
        }
    }
}

/// Leest wat iemand in het veld "Andere repositories" typt of plakt: `eigenaar/repo` (GitHub),
/// `project/repo` (Azure DevOps), `groep/subgroep/project` (GitLab), of een link van github.com,
/// dev.azure.com, gitlab.com of de eigen GitLab-server van het account (`instanceURL`). Geeft de
/// repo in de vorm van `Account.repoWatch`.
public enum RepositoryReference {
    /// GitLab kent een groep met hooguit twintig niveaus subgroepen, plus het project zelf.
    static let gitLabMaxDepth = 22

    /// `instanceURL`: de eigen server van het account. Bij GitHub alleen voor GitHub Enterprise
    /// (een link naar die server telt dan als een GitHub-link); bij GitLab de server (nil is
    /// gitlab.com), en een link moet op die server staan.
    public static func parse(
        _ input: String,
        kind: ProviderKind,
        organization: String,
        instanceURL: URL? = nil
    ) throws(RepositoryProblem) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix(".git") { text.removeLast(4) }
        let instance = kind == .gitLab ? (instanceURL ?? kind.defaultInstanceURL) : nil
        let isLink = text.contains("://") || text.hasPrefix("git@")

        if kind == .gitHub, let instanceURL, let repo = instanceLink(text, instanceURL: instanceURL) {
            return try plain(repo, kind: kind)
        }
        if let link = link(text, gitLabInstance: instance) {
            guard link.kind == kind else { throw .otherService(link.kind) }
            if kind == .azureDevOps, let found = link.organization,
               found.caseInsensitiveCompare(organization) != .orderedSame {
                throw .otherOrganization(found: found, expected: organization)
            }
            if kind == .gitLab, let found = link.organization, let expected = instance?.host()?.lowercased(),
               found != expected {
                throw .otherServer(found: found, expected: expected)
            }
            return try plain(link.repo, kind: kind)
        }
        // Een link naar een onbekende host kan bij GitLab een andere GitLab-server zijn.
        if isLink, kind == .gitLab, let found = host(of: text), let expected = instance?.host()?.lowercased() {
            throw .otherServer(found: found, expected: expected)
        }
        if isLink { throw .unrecognised(kind) }
        return try plain(text, kind: kind)
    }

    /// `a/b` met precies twee delen (GitLab: twee of meer), met de tekens die de dienst toestaat.
    private static func plain(_ text: String, kind: ProviderKind) throws(RepositoryProblem) -> String {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let depth = kind == .gitLab ? 2...gitLabMaxDepth : 2...2
        guard depth.contains(parts.count), parts.allSatisfy({ !$0.isEmpty }) else { throw .unrecognised(kind) }
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
        case .gitLab:
            // GitLab: letters, cijfers, "_", "-" en "."; niet beginnen met "-" of "." (dus ook geen
            // los "-": dat scheidt het project van zijn pagina's, `/-/merge_requests`).
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-."))
            guard parts.allSatisfy({ part in
                part.unicodeScalars.allSatisfy(allowed.contains) && !part.hasPrefix("-") && !part.hasPrefix(".")
            }) else {
                throw .unrecognised(kind)
            }
        }
        return parts.joined(separator: "/")
    }

    /// "https://github.example.com/eigenaar/repo[/…]" (ook zonder schema, of via SSH) op de
    /// eigen server: "eigenaar/repo"; nil als de link niet naar die server wijst.
    private static func instanceLink(_ text: String, instanceURL: URL) -> String? {
        guard let host = instanceURL.host()?.lowercased() else { return nil }
        var text = text
        if text.lowercased().hasPrefix("git@\(host):") {
            text = "https://\(host)/" + text.dropFirst("git@\(host):".count)
        } else if !text.contains("://") {
            text = "https://" + text
        }
        guard let url = URL(string: text), url.host()?.lowercased() == host else { return nil }
        let base = instanceURL.pathComponents.filter { $0 != "/" }
        var path = url.pathComponents.filter { $0 != "/" }
        guard path.starts(with: base) else { return nil }
        path.removeFirst(base.count)
        guard path.count >= 2 else { return "" }
        return "\(path[0])/\(path[1])"
    }

    /// De host van een link (ook `git@host:pad`), in kleine letters.
    private static func host(of text: String) -> String? {
        if text.hasPrefix("git@"), let colon = text.firstIndex(of: ":") {
            let host = text[text.index(text.startIndex, offsetBy: 4)..<colon]
            return host.isEmpty ? nil : host.lowercased()
        }
        return URL(string: text)?.host()?.lowercased()
    }

    /// Een link van een bekende dienst, met de repo erin en (Azure DevOps) de organisatie of
    /// (GitLab) de host. `gitLabInstance` is de server van een GitLab-account; gitlab.com is altijd
    /// bekend.
    private static func link(
        _ text: String,
        gitLabInstance: URL?
    ) -> (kind: ProviderKind, repo: String, organization: String?)? {
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
        let gitLabHost = gitLabInstance?.host()?.lowercased()

        switch host {
        case "github.com", "www.github.com":
            guard path.count >= 2 else { return (.gitHub, "", nil) }
            return (.gitHub, "\(path[0])/\(path[1])", nil)
        case "gitlab.com", "www.gitlab.com":
            return (.gitLab, gitLabPath(path), "gitlab.com")
        case "dev.azure.com":
            // https://dev.azure.com/org/project/_git/repo[/…]
            guard path.count >= 4, path[2] == "_git" else { return (.azureDevOps, "", path.first) }
            return (.azureDevOps, "\(path[1])/\(path[3])", path[0])
        case "ssh.dev.azure.com":
            // ssh://ssh.dev.azure.com/v3/org/project/repo
            guard path.count >= 4, path[0] == "v3" else { return (.azureDevOps, "", nil) }
            return (.azureDevOps, "\(path[2])/\(path[3])", path[1])
        case gitLabHost:
            // De eigen server, eventueel onder een pad (`https://example.com/gitlab/groep/project`);
            // via SSH staat dat pad er niet in.
            let prefix = gitLabInstance?.pathComponents.filter { $0 != "/" } ?? []
            let underPrefix = path.count >= prefix.count
                && zip(path, prefix).allSatisfy { $0.caseInsensitiveCompare($1) == .orderedSame }
            let rest = url.scheme == "ssh" || !underPrefix ? path : Array(path.dropFirst(prefix.count))
            return (.gitLab, gitLabPath(rest), host)
        default:
            // https://org.visualstudio.com/[DefaultCollection/]project/_git/repo
            guard host.hasSuffix(".visualstudio.com") else { return nil }
            let organization = String(host.dropLast(".visualstudio.com".count))
            let rest = path.first?.caseInsensitiveCompare("DefaultCollection") == .orderedSame ? Array(path.dropFirst()) : path
            guard rest.count >= 3, rest[1] == "_git" else { return (.azureDevOps, "", organization) }
            return (.azureDevOps, "\(rest[0])/\(rest[2])", organization)
        }
    }

    /// Het projectpad uit de delen van een GitLab-link: alles vóór `-` (de pagina's van een
    /// project: `/-/tree/main`, `/-/merge_requests/12`). Een groepspagina (`/groups/acme`) of een
    /// gebruikersprofiel (`/users/jdoe`) is geen project.
    private static func gitLabPath(_ path: [String]) -> String {
        let project = Array(path.prefix { $0 != "-" })
        guard let first = project.first?.lowercased(), first != "groups", first != "users" else { return "" }
        return project.joined(separator: "/")
    }
}
