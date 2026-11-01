import Foundation
import Testing
@testable import PullwatchCore

@Suite struct PackageOverviewTests {
    let account = UUID()
    let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    private func go(_ version: String, cycle: String, latest: String) -> ComponentVersion {
        ComponentVersion(product: "go", label: "Go", version: version, latest: "1.27.4", status: .current, sources: ["go.mod"],
                         cycle: cycle, cycleLatest: latest)
    }

    private func repo(_ name: String, components: [ComponentVersion] = [], packages: [PackageUse] = []) -> RepoVersions {
        RepoVersions(accountId: account, repo: name, components: components, packages: packages)
    }

    private func npm(_ name: String, _ version: String) -> PackageUse {
        PackageUse(ecosystem: "npm", name: name, version: version, sources: ["package-lock.json"])
    }

    @Test func behindComparesOnlyTheGivenPrecision() {
        #expect(PackageVersions.isBehind("1.27.3", latest: "1.27.4"))
        #expect(!PackageVersions.isBehind("1.27", latest: "1.27.4"))
        #expect(!PackageVersions.isBehind("1.27.4", latest: "1.27.4"))
        #expect(PackageVersions.isBehind("1.26", latest: "1.27.4"))
        #expect(!PackageVersions.isBehind("2.0.0", latest: "1.9.0"))
    }

    @Test func runtimeRowsArePerCycle() {
        let report = VersionReport(checkedAt: t0, repos: [
            repo("acme/a", components: [go("1.27.3", cycle: "1.27", latest: "1.27.4")]),
            repo("acme/b", components: [go("1.27.4", cycle: "1.27", latest: "1.27.4")]),
            repo("acme/c", components: [go("1.26.10", cycle: "1.26", latest: "1.26.10")]),
        ])
        let summaries = report.packageSummaries()
        let go127 = summaries.first { $0.id == "runtime:go:1.27" }
        #expect(go127?.label == "Go 1.27")
        #expect(go127?.kind == "runtime")
        #expect(go127?.latest == "1.27.4")
        #expect(go127?.state == .updateAvailable)
        #expect(go127?.behind.map(\.repo) == ["acme/a"])
        #expect(go127?.current.map(\.repo) == ["acme/b"])
        #expect(summaries.first { $0.id == "runtime:go:1.26" }?.state == .current)
        #expect(summaries.first?.id == "runtime:go:1.27")
    }

    @Test func frameworksAppearOnlyAsLibrary() {
        let react = ComponentVersion(product: "react", label: "React", version: "19.2.1", latest: "19", status: .current,
                                     sources: ["package-lock.json"], cycle: "19", cycleLatest: "19.3.0")
        let report = VersionReport(checkedAt: t0, repos: [repo("acme/web", components: [react], packages: [npm("react", "19.2.1")])],
                                   latestPackages: ["npm:react": PackageLatest(version: "19.3.0", seenAt: t0)])
        let summaries = report.packageSummaries()
        #expect(summaries.map(\.id) == ["npm:react"])
        #expect(summaries.first?.label == "react")
        #expect(summaries.first?.kind == "npm")
        #expect(summaries.first?.since == t0)
        #expect(summaries.first?.state == .updateAvailable)
    }

    @Test func sameRuntimeTwiceInOneRepoCountsOnceWithOldestVersion() {
        let docker = ComponentVersion(product: "go", label: "Docker golang", version: "1.27.4", latest: "1.27.4", status: .current,
                                      sources: ["Dockerfile"], cycle: "1.27", cycleLatest: "1.27.4")
        let report = VersionReport(checkedAt: t0, repos: [repo("acme/a", components: [docker, go("1.27.3", cycle: "1.27", latest: "1.27.4")])])
        let go127 = report.packageSummaries().first { $0.id == "runtime:go:1.27" }
        #expect(go127?.behind.count == 1)
        #expect(go127?.current.isEmpty == true)
        #expect(go127?.behind.first?.version == "1.27.3")
        #expect(go127?.behind.first?.sources == ["Dockerfile", "go.mod"])
    }

    @Test func packageWithoutLatestIsUnchecked() {
        let report = VersionReport(checkedAt: t0, repos: [repo("acme/a", packages: [npm("@acme/private", "1.0.0"), npm("left-pad", "1.3.0")])],
                                   latestPackages: ["npm:@acme/private": PackageLatest(version: nil, seenAt: t0)])
        #expect(report.packageSummaries().map(\.state) == [.unchecked, .unchecked])
    }

    @Test func sortsUpdatesByRepoCountThenCurrentThenUnchecked() {
        let report = VersionReport(checkedAt: t0, repos: [
            repo("acme/a", packages: [npm("vite", "6.0.0"), npm("zod", "3.0.0"), npm("lodash", "4.17.21"), npm("x", "1.0.0")]),
            repo("acme/b", packages: [npm("zod", "3.0.0")]),
        ], latestPackages: [
            "npm:vite": PackageLatest(version: "6.1.0", seenAt: t0),
            "npm:zod": PackageLatest(version: "3.1.0", seenAt: t0),
            "npm:lodash": PackageLatest(version: "4.17.21", seenAt: t0),
        ])
        #expect(report.packageSummaries().map(\.label) == ["zod", "vite", "lodash", "x"])
    }

    @Test func carriesSeenDateWhileVersionIsUnchanged() {
        let previous = VersionReport(checkedAt: t0, repos: [], latestPackages: [
            "npm:react": PackageLatest(version: "19.3.0", seenAt: t0),
            "npm:vite": PackageLatest(version: "6.0.0", seenAt: t0),
        ])
        let later = t0 + 86_400
        let report = VersionReport(checkedAt: later, repos: [], latestPackages: [
            "npm:react": PackageLatest(version: "19.3.0", seenAt: later),
            "npm:vite": PackageLatest(version: "6.1.0", seenAt: later),
        ]).carryingSeenDates(from: previous)
        #expect(report.latestPackages["npm:react"]?.seenAt == t0)
        #expect(report.latestPackages["npm:vite"]?.seenAt == later)
    }

    @Test func newVersionsOnlyWhenLatestChangedAndSomeoneIsBehind() {
        let repos = [
            repo("acme/a", components: [go("1.27.3", cycle: "1.27", latest: "1.27.4")],
                 packages: [npm("react", "19.2.1"), npm("vite", "6.1.0"), npm("zod", "3.0.0")]),
        ]
        let previousRepos = [
            repo("acme/a", components: [go("1.27.3", cycle: "1.27", latest: "1.27.3")],
                 packages: [npm("react", "19.2.1"), npm("vite", "6.0.0"), npm("zod", "3.0.0")]),
        ]
        let previous = VersionReport(checkedAt: t0, repos: previousRepos, latestPackages: [
            "npm:react": PackageLatest(version: "19.3.0", seenAt: t0),
            "npm:vite": PackageLatest(version: "6.0.0", seenAt: t0),
        ])
        let report = VersionReport(checkedAt: t0, repos: repos, latestPackages: [
            "npm:react": PackageLatest(version: "19.3.0", seenAt: t0), // ongewijzigd
            "npm:vite": PackageLatest(version: "6.1.0", seenAt: t0), // gewijzigd, maar niemand achter
            "npm:zod": PackageLatest(version: "3.1.0", seenAt: t0), // vorige keer onbekend: stil
        ])
        #expect(report.newPackageVersions(since: previous).map(\.id) == ["runtime:go:1.27"])
        #expect(report.newPackageVersions(since: nil).isEmpty)
    }

    @Test func oldReportWithoutPackagesDecodes() throws {
        let json = #"{"checkedAt":0,"repos":[{"accountId":"00000000-0000-0000-0000-000000000001","repo":"acme/a","components":[]}]}"#
        let report = try JSONDecoder().decode(VersionReport.self, from: Data(json.utf8))
        #expect(report.latestPackages.isEmpty)
        #expect(report.repos.first?.packages.isEmpty == true)
    }

    @Test func reportRoundTripsPackages() throws {
        let report = VersionReport(checkedAt: t0, repos: [repo("acme/a", packages: [npm("react", "19.2.1")])],
                                   latestPackages: ["npm:react": PackageLatest(version: "19.3.0", seenAt: t0)])
        let decoded = try JSONDecoder().decode(VersionReport.self, from: JSONEncoder().encode(report))
        #expect(decoded == report)
    }
}
