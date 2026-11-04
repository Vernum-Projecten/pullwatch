import Foundation
import PullwatchCore

/// Welke repo's een agent mag zien: alleen wat Pullwatch volgt. Een repo telt als gevolgd als
/// zijn account hem volgt (PR's, tags of gemerged, ook via de standaard voor nieuwe repo's) en
/// Pullwatch hem kent (in het overzicht, de geschiedenis, de eigen keuzes of de losse repo's).
/// Een andere repo bestaat voor de agent niet; vragen ernaar geeft "not followed".
struct MCPFollowedRepos {
    /// Eén gevolgde repo van één account.
    struct Match {
        let account: Account
        /// De naam zoals Pullwatch hem schrijft (de hoofdletters van de dienst).
        let repo: String
        /// Wat Pullwatch over de repo weet; nil als hij nog niet in het overzicht staat.
        let summary: RepoSummary?
    }

    private let accounts: [Account]
    private let summaries: [RepoSummary]
    /// Per account de repo's uit de geschiedenis, in kleine letters naar de schrijfwijze.
    private let historyRepos: [UUID: [String: String]]

    init(accounts: [Account], summaries: [RepoSummary], history: [HistoryItem]) {
        self.accounts = accounts
        self.summaries = summaries
        var repos: [UUID: [String: String]] = [:]
        for item in history {
            repos[item.entry.accountId, default: [:]][item.entry.repo.lowercased()] = item.entry.repo
        }
        historyRepos = repos
    }

    // MARK: - Lezen

    /// Of `repo` van account `accountId` gevolgd wordt.
    func contains(accountId: UUID, repo: String) -> Bool {
        guard let account = accounts.first(where: { $0.id == accountId }) else { return false }
        return name(of: repo, in: account) != nil
    }

    /// De overzichten van de gevolgde repo's, in de volgorde van het overzicht.
    var followedSummaries: [RepoSummary] {
        summaries.filter { contains(accountId: $0.accountId, repo: $0.repo) }
    }

    /// De gevolgde repo `repo` (hoofdletterongevoelig), eventueel alleen van account `accountId`.
    /// Niet gevolgd, of bij meer accounts zonder `account_id`: een fout die het model kan lezen.
    func resolve(_ repo: String, accountId: String?) throws(MCPToolError) -> Match {
        let candidates = try Self.accounts(accounts, matching: accountId)
        let matches = candidates.compactMap { account in
            name(of: repo, in: account).map { name in
                Match(
                    account: account, repo: name,
                    summary: summaries.first { $0.accountId == account.id && $0.repo.caseInsensitiveCompare(repo) == .orderedSame }
                )
            }
        }
        guard let first = matches.first else {
            throw MCPToolError("Repository \(repo) is not followed in Pullwatch. list_repositories lists the repositories you can ask about.")
        }
        guard matches.count == 1 else {
            let ids = matches.map(\.account.id.uuidString).joined(separator: ", ")
            throw MCPToolError("Repository \(repo) is followed by more than one account (\(ids)); pass account_id to choose one.")
        }
        return first
    }

    /// Het account met `id`, of alle accounts zonder id. Een id dat er niet is: een fout.
    static func accounts(_ accounts: [Account], matching id: String?) throws(MCPToolError) -> [Account] {
        guard let id else { return accounts }
        guard let uuid = UUID(uuidString: id), let account = accounts.first(where: { $0.id == uuid }) else {
            throw MCPToolError("No account has the id \(id). get_status lists the accounts with their ids.")
        }
        return [account]
    }

    /// De schrijfwijze van `repo` als `account` hem volgt en Pullwatch hem kent; anders nil.
    private func name(of repo: String, in account: Account) -> String? {
        let watch = account.watch(for: repo)
        guard watch.prs || watch.tags || watch.completed else { return nil }
        if let summary = summaries.first(where: { $0.accountId == account.id && $0.repo.caseInsensitiveCompare(repo) == .orderedSame }) {
            return summary.repo
        }
        if let known = historyRepos[account.id]?[repo.lowercased()] { return known }
        let configured = Array(account.repoWatch.keys) + account.extraRepos
        return configured.first { $0.caseInsensitiveCompare(repo) == .orderedSame }
    }
}
