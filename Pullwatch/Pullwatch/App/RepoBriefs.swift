import AppKit
import PullwatchCore
import SwiftUI

/// Elk kopje van de pagina als opdracht voor een AI-agent (`AgentBrief`, Markdown in het Engels),
/// zoals de knoppen achter de kopjes en het menu Meer ze kopiëren. De tekst wordt pas bij de klik
/// gemaakt.
struct RepoBriefs {
    let summary: RepoSummary
    let account: Account?
    let accounts: AccountsModel
    let versions: VersionsModel
    let history: HistoryModel

    /// De PR's van de repo zoals Overzicht ze toont: open eerst, daarna de rest op volgorde van
    /// binnenkomst; hoogstens tien.
    static func pullRequests(of summary: RepoSummary, in history: History) -> [HistoryItem] {
        let items = history.items.filter {
            $0.entry.kind == .pullRequest && $0.entry.accountId == summary.accountId
                && $0.entry.repo.caseInsensitiveCompare(summary.repo) == .orderedSame
        }
        return Array((items.filter { $0.entry.prState == .open } + items.filter { $0.entry.prState != .open }).prefix(10))
    }

    /// De kop van een opdracht; `checkedAt` nil neemt de laatste versiecheck.
    private func repository(checkedAt: Date? = nil) -> AgentBrief.Repository {
        AgentBrief.Repository(
            name: summary.repo, url: account?.repoWebURL(summary.repo),
            checkedAt: checkedAt ?? (summary.versions == nil ? nil : versions.versionReport?.checkedAt)
        )
    }

    func pullRequests() -> String {
        AgentBrief.pullRequests(
            repository(checkedAt: Date()), items: Self.pullRequests(of: summary, in: history.history), openCount: summary.openPullRequests
        )
    }

    func pullRequestsPerMonth() -> String {
        AgentBrief.pullRequestsPerMonth(
            repository(checkedAt: Date()),
            stats: history.activityStats(period: .month, filter: ActivityFilter(repoId: summary.id))
        )
    }

    /// Controle: runtimes en kwetsbaarheden; nil zolang de repo niet gecheckt is.
    func vulnerabilities() -> String? {
        guard let repoVersions = summary.versions else { return nil }
        return AgentBrief.vulnerabilities(
            repository(), versions: repoVersions, advisories: summary.advisories,
            advisoryDetailsOff: !accounts.config.isEnabled(.gitHubAdvisoryDatabase),
            context: versions.updateContext(for: repoVersions)
        )
    }

    func packageUpdates() -> String {
        AgentBrief.packageUpdates(
            repository(), repoId: summary.id, updates: summary.packageUpdates,
            skipped: summary.versions?.skippedVersionSources ?? []
        )
    }

    /// De workspaces met packages, elk een eigen opdracht.
    var workspaces: [PackageWorkspace] {
        guard let repoVersions = summary.versions, repoVersions.error == nil else { return [] }
        return repoVersions.packageWorkspaces.filter { !$0.isEmpty }
    }

    func packages(_ workspace: PackageWorkspace) -> String {
        guard let repoVersions = summary.versions else { return "" }
        return AgentBrief.packages(
            repository(), workspace: workspace, showsWorkspace: workspaces.count > 1,
            latest: versions.versionReport?.latestPackages ?? [:],
            context: versions.updateContext(for: repoVersions), skipped: repoVersions.skippedSources
        )
    }

    var provider: ProviderKind { account?.kind ?? .gitHub }

    func security() -> String {
        AgentBrief.security(
            repository(), provider: provider, scan: summary.versions?.security, skipped: summary.versions?.skippedSecuritySource
        )
    }
}
