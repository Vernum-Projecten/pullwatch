import Foundation
import Testing
@testable import PullwatchCore

@Suite struct UpdateCategoryTests {
    let account = UUID()
    let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    private func repo(_ name: String, packages: [PackageUse] = [], vulnerabilities: [Vulnerability] = [],
                      components: [ComponentVersion] = []) -> RepoVersions {
        RepoVersions(accountId: account, repo: name, components: components, vulnerabilities: vulnerabilities, packages: packages)
    }

    private func npm(_ name: String, _ version: String, requested: String?) -> PackageUse {
        PackageUse(ecosystem: "npm", name: name, installs: [
            PackageInstall(version: version, workspace: "", scope: .direct, source: "package-lock.json", requested: requested),
        ])
    }

    private func report(_ repos: [RepoVersions], latest: [String: String]) -> VersionReport {
        VersionReport(checkedAt: t0, repos: repos, latestPackages: latest.mapValues { PackageLatest(version: $0, seenAt: t0) })
    }

    @Test func statusMapsOntoCategory() {
        #expect(PackageUpdate.Status.upToDate.category == .upToDate)
        #expect(PackageUpdate.Status.withinRange.category == .canUpdateNow)
        #expect(PackageUpdate.Status.needsManifestChange.category == .needsManifestChange)
        #expect(PackageUpdate.Status.blockedByPackage(parent: "express", parentRange: "~6.11.0", minimumParentVersion: "4.21.0").category == .blocked)
        #expect(PackageUpdate.Status.blockedByPeer(name: "react", needs: "^19.0.0", installed: "18.3.1").category == .blocked)
        #expect(PackageUpdate.Status.blockedByRuntime(runtime: "nodejs", needs: ">=20", installed: "18").category == .blocked)
        #expect(PackageUpdate.Status.unknown.category == .unknown)
        #expect(UpdateCategory.allCases.sorted() == [.canUpdateNow, .needsManifestChange, .blocked, .unknown, .upToDate])
    }

    /// Een package telt als "nu bij te werken" zodra één repo dat kan; anders manifest, dan geblokkeerd.
    @Test func packageTakesTheMostActionableRepo() {
        let summaries = report([
            repo("acme/a", packages: [npm("lodash", "4.17.20", requested: "^4.17.0"), npm("react", "18.3.1", requested: "^18.3.1")]),
            repo("acme/b", packages: [npm("lodash", "4.17.21", requested: "^4.17.0"), npm("react", "18.2.0", requested: "~18.2.0")]),
            repo("acme/c", packages: [npm("vite", "5.0.0", requested: "^5.0.0"), npm("zod", "3.0.0", requested: nil)]),
        ], latest: ["npm:lodash": "4.17.21", "npm:react": "19.1.0", "npm:vite": "5.0.0", "npm:zod": "3.1.0"]).packageSummaries()
        let byId = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0) })
        #expect(byId["npm:lodash"]?.category == .canUpdateNow)
        #expect(byId["npm:lodash"]?.canUpdateNowCount == 1)
        #expect(byId["npm:react"]?.category == .needsManifestChange)
        #expect(byId["npm:react"]?.canUpdateNowCount == 0)
        #expect(byId["npm:vite"]?.category == .upToDate)
        #expect(byId["npm:zod"]?.category == .unknown, "zonder bereik is niet te zeggen of het kan")
    }

    @Test func runtimeBehindWithinItsCycleCanUpdateNow() {
        let go = ComponentVersion(product: "go", label: "Go", version: "1.27.3", latest: "1.27.4", status: .behind, sources: ["go.mod"],
                                  cycle: "1.27", cycleLatest: "1.27.4")
        let summary = report([repo("acme/a", components: [go])], latest: [:]).packageSummaries().first
        #expect(summary?.category == .canUpdateNow)
    }

    @Test func packageWithoutLatestIsUnknown() {
        let summary = report([repo("acme/a", packages: [npm("lodash", "4.17.20", requested: "^4.17.0")])], latest: [:])
            .packageSummaries().first
        #expect(summary?.category == .unknown)
    }

    /// De badge telt alleen wat je nu kunt nemen, plus wat een kwetsbaarheid oplost.
    @Test func badgeCountsUpdatesYouCanTakeAndSecurityFixes() {
        let react = Vulnerability(id: "GHSA-1", cve: nil, summary: nil, severity: "HIGH", ecosystem: "npm", package: "react",
                                  version: "18.3.1", fixedIn: "19.0.0", source: "package-lock.json", scope: .direct)
        let unfixed = Vulnerability(id: "GHSA-2", cve: nil, summary: nil, severity: "LOW", ecosystem: "npm", package: "vite",
                                    version: "5.0.0", fixedIn: nil, source: "package-lock.json", scope: .direct)
        let report = report([
            repo("acme/a", packages: [
                npm("lodash", "4.17.20", requested: "^4.17.0"), npm("react", "18.3.1", requested: "^18.3.1"),
                npm("vite", "5.0.0", requested: "^5.0.0"), npm("zod", "3.0.0", requested: "~3.0.0"),
            ], vulnerabilities: [react, unfixed]),
        ], latest: ["npm:lodash": "4.17.21", "npm:react": "19.1.0", "npm:vite": "6.0.0", "npm:zod": "3.1.0"])
        #expect(report.packagesWithSecurityFixes == ["npm:react"])
        let summaries = report.packageSummaries()
        #expect(PackageVersions.badgeCount(summaries, seen: [:], securityFixes: report.packagesWithSecurityFixes) == 2)
        #expect(PackageVersions.badgeCount(summaries, seen: ["npm:lodash": "4.17.21"], securityFixes: report.packagesWithSecurityFixes) == 1)
        #expect(PackageVersions.badgeCount(summaries, seen: [:], securityFixes: []) == 1)
    }

    @Test func newVersionNotificationCanBeLimitedToUpdatesYouCanTake() {
        let packages = [npm("lodash", "4.17.20", requested: "^4.17.0"), npm("react", "18.3.1", requested: "^18.3.1")]
        let before = report([repo("acme/a", packages: packages)], latest: ["npm:lodash": "4.17.20", "npm:react": "18.3.1"])
        let after = report([repo("acme/a", packages: packages)], latest: ["npm:lodash": "4.17.21", "npm:react": "19.1.0"])
        #expect(Set(after.newPackageVersions(since: before, onlyCanUpdateNow: false).map(\.id)) == ["npm:lodash", "npm:react"])
        #expect(after.newPackageVersions(since: before, onlyCanUpdateNow: true).map(\.id) == ["npm:lodash"])
    }

    @Test func oldConfigNotifiesOnlyUpdatesYouCanTake() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"accounts":[],"pollInterval":120}"#.utf8))
        #expect(config.notifyOnlyUpdatesYouCanTake)
        let off = AppConfig(notifyOnlyUpdatesYouCanTake: false)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(off))
        #expect(!decoded.notifyOnlyUpdatesYouCanTake)
    }
}
