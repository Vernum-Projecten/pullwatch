import Foundation

/// Hoe een repo ervoor staat: rood (CVE's, EOL of open critical- en high-meldingen van code
/// scanning of Advanced Security), oranje (runtime achter of packages met een nieuwe
/// versie), groen, of grijs (nog niet gecheckt of de check mislukte).
public enum RepoHealth: Hashable, Sendable {
    case problem, behind, ok, unknown

    var rank: Int {
        switch self {
        case .problem: 0
        case .behind: 1
        case .unknown: 2
        case .ok: 3
        }
    }
}

/// Eén gevolgde repo met alles wat Pullwatch erover weet.
public struct RepoSummary: Hashable, Sendable, Identifiable {
    /// Zelfde als `RepoVersions.id` en `PackageUser.repoId`: "<accountId>/<repo>".
    public let id: String
    public let accountId: UUID
    public let repo: String
    public let group: HistoryGroup.ID
    /// nil als de repo nog niet gecheckt is.
    public let versions: RepoVersions?
    public let openPullRequests: Int
    public let latestTag: String?
    public let packageUpdates: [PackageSummary]
    /// GitHubs advies per kwetsbaarheid (`Vulnerability.id`), uit de Advisory Database.
    public let advisories: [String: GitHubAdvisory]

    /// Open critical- en high-meldingen van de dienst zelf.
    public var seriousSecurityAlerts: [SecurityAlert] { versions?.security?.seriousAlerts ?? [] }

    public var health: RepoHealth {
        guard let versions, versions.error == nil else { return .unknown }
        if !versions.vulnerabilities.isEmpty || versions.worstStatus == .eol || !seriousSecurityAlerts.isEmpty { return .problem }
        if versions.worstStatus == .behind || !packageUpdates.isEmpty { return .behind }
        return .ok
    }
}

public enum RepoOverview {
    /// Repo's uit de laatste versiecheck plus repo's die expliciet gevolgd worden maar nog niet gecheckt
    /// zijn. Slechtste eerst, dan op naam. Accountfouten in het rapport (naam zonder "/") tellen niet.
    /// `packageSummaries` mag al uitgerekend meegegeven worden (`report.packageSummaries()`).
    public static func summaries(
        accounts: [Account], report: VersionReport?, history: History, packageSummaries: [PackageSummary]? = nil
    ) -> [RepoSummary] {
        let packageSummaries = packageSummaries ?? report?.packageSummaries() ?? []
        var entries: [(accountId: UUID, repo: String, versions: RepoVersions?)] = []
        for versions in report?.repos ?? [] where versions.repo.contains("/") {
            entries.append((versions.accountId, versions.repo, versions))
        }
        for account in accounts {
            for (repo, watch) in account.repoWatch where watch.prs || watch.tags || watch.completed {
                let known = entries.contains { $0.accountId == account.id && $0.repo.caseInsensitiveCompare(repo) == .orderedSame }
                if !known { entries.append((account.id, repo, nil)) }
            }
        }
        // Eén keer indelen per repo en per repo-id, niet per repo de hele geschiedenis doorzoeken.
        struct RepoKey: Hashable {
            let accountId: UUID
            let repo: String
            init(_ accountId: UUID, _ repo: String) {
                self.accountId = accountId
                self.repo = repo.lowercased()
            }
        }
        let itemsByRepo = Dictionary(grouping: history.items) { RepoKey($0.entry.accountId, $0.entry.repo) }
        var updatesByRepo: [String: [PackageSummary]] = [:]
        for summary in packageSummaries {
            for user in summary.behind { updatesByRepo[user.repoId, default: []].append(summary) }
        }
        return entries.map { entry in
            let id = "\(entry.accountId.uuidString)/\(entry.repo)"
            let items = itemsByRepo[RepoKey(entry.accountId, entry.repo)] ?? []
            return RepoSummary(
                id: id,
                accountId: entry.accountId,
                repo: entry.repo,
                group: HistoryGroup.ID(accountId: entry.accountId, repo: entry.repo),
                versions: entry.versions,
                openPullRequests: items.filter { $0.entry.prState == .open }.count,
                latestTag: items.filter { $0.entry.kind == .tag }.max { $0.detectedAt < $1.detectedAt }?.entry.title
                    ?? entry.versions?.release?.tag,
                packageUpdates: updatesByRepo[id] ?? [],
                advisories: Self.advisories(of: entry.versions, in: report)
            )
        }
        .sorted {
            if $0.health.rank != $1.health.rank { return $0.health.rank < $1.health.rank }
            return $0.repo.localizedCaseInsensitiveCompare($1.repo) == .orderedAscending
        }
    }

    /// GitHubs advies bij elke kwetsbaarheid van de repo, ook die van de laatste release.
    static func advisories(of versions: RepoVersions?, in report: VersionReport?) -> [String: GitHubAdvisory] {
        guard let versions, let report, !report.advisories.isEmpty else { return [:] }
        var result: [String: GitHubAdvisory] = [:]
        for vulnerability in versions.vulnerabilities + (versions.release?.vulnerabilities ?? []) where result[vulnerability.id] == nil {
            result[vulnerability.id] = report.advisory(for: vulnerability)
        }
        return result
    }

    /// Projecten met als teller het aantal repo's met CVE's of EOL.
    public static func groups(_ summaries: [RepoSummary], accountNames: [UUID: String]) -> [HistoryGroup] {
        var problems: [HistoryGroup.ID: Int] = [:]
        for summary in summaries {
            problems[summary.group, default: 0] += summary.health == .problem ? 1 : 0
        }
        return HistoryGroup.named(problems, accountNames: accountNames)
    }
}
