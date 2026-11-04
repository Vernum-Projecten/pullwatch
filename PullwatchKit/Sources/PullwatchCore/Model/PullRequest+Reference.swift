import Foundation

/// Hoe een pull request naar zichzelf verwijst, zoals de dienst het schrijft:
/// `FerroHEALTH/FerroFED#1570` op GitHub, `group/sub/project!42` op GitLab, `project/repo!42` op
/// Azure DevOps. Het teken komt van `ProviderKind.pullRequestPrefix`; de PR zelf weet niet bij
/// welke dienst hij hoort, dus de aanroeper geeft de dienst van zijn account mee.
extension PullRequest {
    /// Het nummer met het teken van de dienst: `#1570` of `!42`.
    public func numberText(_ kind: ProviderKind) -> String {
        "\(kind.pullRequestPrefix)\(number)"
    }

    /// De volledige verwijzing zonder spatie, zoals in een commit of issue: `FerroHEALTH/FerroFED#1570`.
    public func reference(_ kind: ProviderKind) -> String {
        "\(repo)\(numberText(kind))"
    }

    /// De korte naam van de repo met het nummer, zoals GitHub het in lijsten toont: `FerroFED #1570`.
    public func shortReference(_ kind: ProviderKind) -> String {
        "\(Self.shortName(of: repo)) \(numberText(kind))"
    }

    /// De repo voluit met het nummer, waar de eigenaar ertoe doet (een melding):
    /// `FerroHEALTH/FerroFED #1570`.
    public func repoAndNumber(_ kind: ProviderKind) -> String {
        "\(repo) \(numberText(kind))"
    }

    /// Het laatste deel van een repo-pad: `FerroFED` van `FerroHEALTH/FerroFED`, `project` van
    /// `group/sub/project`, `repo` van `project/repo` (Azure DevOps).
    public static func shortName(of repo: String) -> String {
        repo.split(separator: "/").last.map(String.init) ?? repo
    }
}

extension HistoryEntry {
    /// De volledige verwijzing van een PR (`FerroHEALTH/FerroFED#1570`); nil voor een tag.
    public func reference(_ kind: ProviderKind) -> String? {
        guard case .pullRequest(let pr) = self else { return nil }
        return pr.reference(kind)
    }

    /// Het nummer van een PR; nil voor een tag.
    public var pullRequestNumber: Int? {
        guard case .pullRequest(let pr) = self else { return nil }
        return pr.number
    }
}
