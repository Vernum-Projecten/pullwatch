import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct RepoOverviewTests {
    let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    private func account(_ kind: ProviderKind = .azureDevOps, watch: [String: WatchSet] = [:]) -> Account {
        Account(id: fixedAccountId, kind: kind, organization: "code24-nl", authMethod: .pat,
                repoWatch: watch, newRepoDefault: .none)
    }

    private func component(_ status: VersionStatus) -> ComponentVersion {
        ComponentVersion(product: "go", label: "Go", version: "1.26.9", latest: "1.27.4", status: status, sources: ["go.mod"],
                         cycle: "1.26", cycleLatest: "1.26.9")
    }

    private func vulnerability() -> Vulnerability {
        Vulnerability(id: "GHSA-1", cve: "CVE-2026-1", summary: nil, severity: "HIGH", ecosystem: "Go", package: "x",
                      version: "1.0.0", fixedIn: "1.0.1", source: "go.mod")
    }

    @Test func webURLs() {
        #expect(account().repoWebURL("tools24/container-scanning")?.absoluteString
            == "https://dev.azure.com/code24-nl/tools24/_git/container-scanning")
        #expect(account(.gitHub).repoWebURL("alessandro823/pullwatch")?.absoluteString == "https://github.com/alessandro823/pullwatch")
    }

    @Test func healthAndOrderWorstFirst() {
        let report = VersionReport(checkedAt: t0, repos: [
            RepoVersions(accountId: fixedAccountId, repo: "P/ok", components: [component(.current)]),
            RepoVersions(accountId: fixedAccountId, repo: "P/cve", components: [component(.current)], vulnerabilities: [vulnerability()]),
            RepoVersions(accountId: fixedAccountId, repo: "P/behind", components: [component(.behind)]),
            RepoVersions(accountId: fixedAccountId, repo: "P/eol", components: [component(.eol)]),
            RepoVersions(accountId: fixedAccountId, repo: "P/broken", components: [], error: "Netwerkfout"),
        ])
        let summaries = RepoOverview.summaries(accounts: [account()], report: report, history: History())
        #expect(summaries.map(\.repo) == ["P/cve", "P/eol", "P/behind", "P/broken", "P/ok"])
        #expect(summaries.map(\.health) == [.problem, .problem, .behind, .unknown, .ok])
    }

    /// Een bron die uit stond zegt niets over de repo: dan niet "actueel", wel een probleem als dat er is.
    @Test func skippedSourceIsNeverOk() {
        let report = VersionReport(checkedAt: t0, repos: [
            RepoVersions(accountId: fixedAccountId, repo: "P/off", components: [component(.current)], skippedSources: [.osv]),
            RepoVersions(accountId: fixedAccountId, repo: "P/eol", components: [component(.eol)], skippedSources: [.npm]),
        ])
        let summaries = Dictionary(uniqueKeysWithValues: RepoOverview.summaries(accounts: [account()], report: report, history: History())
            .map { ($0.repo, $0.health) })
        #expect(summaries["P/off"] == .unknown)
        #expect(summaries["P/eol"] == .problem)
    }

    @Test func packageUpdatesMakeARepoBehind() {
        let report = VersionReport(checkedAt: t0, repos: [
            RepoVersions(accountId: fixedAccountId, repo: "P/web", components: [],
                         packages: [PackageUse(ecosystem: "npm", name: "vite", version: "6.0.0", sources: ["package-lock.json"])]),
        ], latestPackages: ["npm:vite": PackageLatest(version: "6.1.0", seenAt: t0)])
        let summary = RepoOverview.summaries(accounts: [account()], report: report, history: History()).first
        #expect(summary?.health == .behind)
        #expect(summary?.packageUpdates.map(\.label) == ["vite"])
    }

    @Test func followedButUncheckedRepoIsListedOnceAndAccountErrorsAreNot() {
        let watch = ["p/new": WatchSet(prs: true, tags: false), "P/Known": WatchSet(prs: true, tags: false),
                     "p/ignored": WatchSet(prs: false, tags: false)]
        let report = VersionReport(checkedAt: t0, repos: [
            RepoVersions(accountId: fixedAccountId, repo: "P/known", components: [component(.current)]),
            RepoVersions(accountId: fixedAccountId, repo: "Werk", components: [], error: "Token ongeldig"),
        ])
        let summaries = RepoOverview.summaries(accounts: [account(watch: watch)], report: report, history: History())
        #expect(summaries.map(\.repo) == ["p/new", "P/known"])
        #expect(summaries.first?.health == .unknown)
        #expect(summaries.first?.versions == nil)
    }

    @Test func countsOpenPullRequestsAndUsesNewestTag() {
        var history = History()
        history.add(pullRequests: [
            .fixture(repo: "P/api", number: 1),
            .fixture(repo: "P/api", number: 2, state: .merged),
            .fixture(repo: "P/other", number: 3),
        ], tags: [.fixture(repo: "P/api", name: "v1.0.0")], at: t0)
        history.add(pullRequests: [], tags: [.fixture(repo: "P/api", name: "v1.1.0")], at: t0 + 60)
        let summaries = RepoOverview.summaries(accounts: [account(watch: ["P/api": .prs])], report: nil, history: history)
        #expect(summaries.first?.openPullRequests == 1)
        #expect(summaries.first?.latestTag == "v1.1.0")
    }

    @Test func groupsCountProblemRepos() {
        let report = VersionReport(checkedAt: t0, repos: [
            RepoVersions(accountId: fixedAccountId, repo: "FerroHEALTH/portal", components: [component(.eol)]),
            RepoVersions(accountId: fixedAccountId, repo: "FerroHEALTH/api", components: [component(.current)]),
            RepoVersions(accountId: fixedAccountId, repo: "tools24/scan", components: [component(.current)]),
        ])
        let summaries = RepoOverview.summaries(accounts: [account()], report: report, history: History())
        let groups = RepoOverview.groups(summaries, accountNames: [fixedAccountId: "Werk"])
        #expect(groups.map(\.name) == ["FerroHEALTH", "tools24"])
        #expect(groups.map(\.unreadCount) == [1, 0])
    }
}
