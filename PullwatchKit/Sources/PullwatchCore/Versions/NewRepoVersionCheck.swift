import Foundation

/// Of de repo's die na een poll gevolgd worden een eigen versiecheck nodig hebben, zonder op de
/// dagelijkse te wachten: net gevolgd, of nieuw bij de dienst. De app beslist met dit oordeel en
/// start de check zelf.
public enum NewRepoVersionCheck {
    /// Wat er per account gevolgd wordt. Verandert dat sinds de vorige check, dan is er een
    /// nieuwe nodig.
    public static func scope(of accounts: [Account]) -> [UUID: FilterSettings] {
        Dictionary(accounts.map { ($0.id, $0.filterSettings) }, uniquingKeysWith: { first, _ in first })
    }

    /// Of `result` een repo bevat die gevolgd wordt (PR's, tags of afgeronde PR's), nog niet in
    /// `report` staat en nog niet los gecheckt is (`attempted`, sleutels van `Account.repoKey`).
    static func hasUnseenRepo(
        in result: PollResult, accounts: [Account], report: VersionReport, attempted: Set<String>
    ) -> Bool {
        let known = Set(report.repos.map { Account.repoKey(accountId: $0.accountId, repo: $0.repo) })
        var seen: [(UUID, String)] = result.tagRepos.flatMap { id, repos in repos.map { (id, $0) } }
        seen += (result.syncedPullRequests + result.newPullRequests).map { ($0.accountId, $0.repo) }
        seen += result.syncedTags.map { ($0.accountId, $0.repo) }
        return seen.contains { id, repo in
            let key = Account.repoKey(accountId: id, repo: repo)
            guard let account = accounts.first(where: { $0.id == id }), !known.contains(key),
                  !attempted.contains(key) else { return false }
            let watch = account.watch(for: repo)
            return watch.prs || watch.tags || watch.completed
        }
    }

    /// Of er na deze poll een check van de nieuwe repo's moet komen: wat gevolgd wordt is
    /// veranderd sinds `lastScope`, of de poll zag een repo die nog niet gecheckt is.
    public static func isNeeded(
        after result: PollResult, accounts: [Account], report: VersionReport,
        attempted: Set<String>, lastScope: [UUID: FilterSettings]?
    ) -> Bool {
        scope(of: accounts) != lastScope
            || hasUnseenRepo(in: result, accounts: accounts, report: report, attempted: attempted)
    }
}

extension Account {
    /// Sleutel van een repo bij een account, ongevoelig voor hoofdletters: `<accountId>/<repo>`.
    public static func repoKey(accountId: UUID, repo: String) -> String {
        "\(accountId.uuidString)/\(repo.lowercased())"
    }
}
