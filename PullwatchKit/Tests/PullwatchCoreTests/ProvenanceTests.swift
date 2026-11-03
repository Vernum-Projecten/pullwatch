import Foundation
import Testing
@testable import PullwatchCore

/// Herkomst op de repo-pagina en in Versies: adviezen per lek, packages per workspace, en repo's
/// die een package alleen transitief hebben.
@Suite struct ProvenanceTests {
    let account = UUID()
    let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    private func vuln(
        _ id: String, _ package: String, _ version: String, severity: String = "HIGH", fixedIn: String? = "4.17.21",
        workspace: String = "", scope: DependencyScope = .direct, kind: DependencyKind = .runtime, via: [String] = []
    ) -> Vulnerability {
        Vulnerability(id: id, cve: nil, summary: nil, severity: severity, ecosystem: "npm", package: package, version: version,
                      fixedIn: fixedIn, source: workspace.isEmpty ? "package-lock.json" : "\(workspace)/package-lock.json",
                      workspace: workspace, scope: scope, kind: kind, via: via)
    }

    @Test func oneAdvisoryPerLeakWithEveryInstallDirectFirst() throws {
        let repo = RepoVersions(accountId: account, repo: "acme/mono", components: [], vulnerabilities: [
            vuln("GHSA-1", "lodash", "4.17.15", workspace: "packages/api", scope: .transitive, via: ["express"]),
            vuln("GHSA-1", "lodash", "4.17.20"),
            vuln("GHSA-2", "qs", "6.5.0", severity: "CRITICAL", fixedIn: "6.5.3", scope: .transitive, via: ["express", "body-parser"]),
            vuln("GHSA-3", "jest-util", "1.0.0", severity: "LOW", fixedIn: nil, kind: .dev),
        ])
        #expect(repo.advisoryCount == 3)
        let advisories = repo.advisories
        // Direct eerst (ernstigste eerst), daarna transitief, ook al is dat kritiek.
        #expect(advisories.map(\.first.id) == ["GHSA-1", "GHSA-3", "GHSA-2"])
        let lodash = try #require(advisories.first)
        #expect(lodash.installs.map(\.version) == ["4.17.20", "4.17.15"])
        #expect(lodash.isDirect)
        #expect(!lodash.isDevOnly)
        #expect(advisories[1].isDevOnly)
        #expect(!advisories[2].isDirect)
    }

    @Test func fixNamesWhatToUpdate() {
        #expect(vuln("GHSA-1", "lodash", "4.17.20").fix == .update(package: "lodash", to: "4.17.21"))
        #expect(vuln("GHSA-2", "qs", "6.5.0", fixedIn: "6.5.3", scope: .transitive, via: ["express", "body-parser"]).fix
                == .updateParent(parent: "express", package: "qs", minimum: "6.5.3"))
        // Transitief zonder bekende keten: dan het package zelf.
        #expect(vuln("GHSA-2", "qs", "6.5.0", fixedIn: "6.5.3", scope: .transitive).fix == .update(package: "qs", to: "6.5.3"))
        #expect(vuln("GHSA-3", "x", "1.0.0", fixedIn: nil).fix == .none)
    }

    @Test func newVulnerabilityNotifiesOncePerAdvisoryWithTheDirectInstall() throws {
        let before = VersionReport(checkedAt: t0, repos: [RepoVersions(accountId: account, repo: "acme/mono", components: [])])
        let after = VersionReport(checkedAt: t0, repos: [RepoVersions(accountId: account, repo: "acme/mono", components: [], vulnerabilities: [
            vuln("GHSA-1", "lodash", "4.17.15", workspace: "packages/api", scope: .transitive, via: ["express"]),
            vuln("GHSA-1", "lodash", "4.17.20"),
        ])])
        let found = after.newVulnerabilities(since: before)
        #expect(found.count == 1)
        #expect(try #require(found.first).vulnerability.scope == .direct)
    }

    @Test func packagesPerWorkspaceInDirectTransitiveUnknownAndDev() throws {
        let lodash = PackageUse(ecosystem: "npm", name: "lodash", installs: [
            PackageInstall(version: "4.17.21", workspace: "", scope: .direct, source: "package-lock.json"),
            PackageInstall(version: "4.17.15", workspace: "", scope: .transitive, via: ["express", "body-parser"], source: "package-lock.json"),
            PackageInstall(version: "4.17.20", workspace: "packages/web", scope: .transitive, via: ["react-scripts"], source: "package-lock.json"),
        ])
        let jest = PackageUse(ecosystem: "npm", name: "jest", installs: [
            PackageInstall(version: "29.0.0", workspace: "", scope: .direct, kind: .dev, source: "package-lock.json"),
        ])
        let qs = PackageUse(ecosystem: "npm", name: "qs", installs: [
            PackageInstall(version: "6.5.0", workspace: "", scope: .transitive, via: ["express"], source: "package-lock.json"),
        ])
        let six = PackageUse(ecosystem: "PyPI", name: "six", installs: [
            PackageInstall(version: "1.16.0", workspace: "tools", scope: .unknown, source: "tools/poetry.lock"),
        ])
        let repo = RepoVersions(accountId: account, repo: "acme/mono", components: [], packages: [lodash, jest], otherPackages: [qs, six])
        let workspaces = repo.packageWorkspaces
        #expect(workspaces.map(\.workspace) == ["", "packages/web", "tools"])
        let root = try #require(workspaces.first)
        #expect(root.direct.map(\.name) == ["lodash"])
        #expect(root.direct.first?.installs.map(\.version) == ["4.17.21", "4.17.15"])
        #expect(root.direct.first?.repoVersions == ["4.17.15", "4.17.20", "4.17.21"])
        #expect(root.transitive.map(\.name) == ["qs"])
        #expect(root.dev.map(\.name) == ["jest"])
        #expect(workspaces[1].transitive.map(\.name) == ["lodash"])
        #expect(workspaces[2].unknown.map(\.name) == ["six"])
    }

    @Test func transitiveOnlyUsersAreMarkedAndNeverBehind() throws {
        let direct = PackageUse(ecosystem: "npm", name: "lodash", installs: [
            PackageInstall(version: "4.17.21", workspace: "", scope: .direct, source: "package-lock.json"),
        ])
        let pulledIn = PackageUse(ecosystem: "npm", name: "lodash", installs: [
            PackageInstall(version: "4.17.15", workspace: "", scope: .transitive, via: ["express"], source: "package-lock.json"),
        ])
        let nowhereDirect = PackageUse(ecosystem: "npm", name: "qs", installs: [
            PackageInstall(version: "6.5.0", workspace: "", scope: .transitive, via: ["express"], source: "package-lock.json"),
        ])
        let report = VersionReport(checkedAt: t0, repos: [
            RepoVersions(accountId: account, repo: "acme/api", components: [], otherPackages: [pulledIn, nowhereDirect]),
            RepoVersions(accountId: account, repo: "acme/web", components: [], packages: [direct]),
        ], latestPackages: ["npm:lodash": PackageLatest(version: "4.17.21", seenAt: t0)])
        let summaries = report.packageSummaries()
        #expect(summaries.map(\.id) == ["npm:lodash"])
        let lodash = try #require(summaries.first)
        #expect(lodash.state == .current)
        #expect(lodash.behind.isEmpty)
        #expect(lodash.current.map(\.repo) == ["acme/web"])
        #expect(lodash.transitiveOnly.map(\.repo) == ["acme/api"])
        #expect(lodash.transitiveOnly.first?.isTransitiveOnly == true)
        #expect(lodash.transitiveOnly.first?.installs.first?.via == ["express"])
    }

    @Test func otherPackagesRoundTripAndOldJsonHasNone() throws {
        let qs = PackageUse(ecosystem: "npm", name: "qs", installs: [
            PackageInstall(version: "6.5.0", workspace: "", scope: .transitive, via: ["express"], source: "package-lock.json"),
        ])
        let repo = RepoVersions(accountId: account, repo: "acme/api", components: [], otherPackages: [qs])
        let decoded = try JSONDecoder().decode(RepoVersions.self, from: JSONEncoder().encode(repo))
        #expect(decoded.otherPackages == [qs])
        let old = #"{"accountId":"\#(account.uuidString)","repo":"acme/api","components":[]}"#
        #expect(try JSONDecoder().decode(RepoVersions.self, from: Data(old.utf8)).otherPackages.isEmpty)
    }

    @Test func scanKeepsPackagesThatAreNotDirectAsOtherPackages() {
        var scan = VersionChecker.Scan()
        scan.dependencies = [
            Dependency(ecosystem: "npm", name: "express", version: "4.18.0", source: "package-lock.json", workspace: "", scope: .direct),
            Dependency(ecosystem: "npm", name: "qs", version: "6.5.0", source: "package-lock.json", workspace: "", scope: .transitive, via: ["express"]),
            Dependency(ecosystem: "npm", name: "qs", version: "6.11.0", source: "web/package-lock.json", workspace: "web", scope: .transitive, via: ["express"]),
        ]
        #expect(scan.directDependencies.map(\.name) == ["express"])
        #expect(scan.otherPackages.map(\.name) == ["qs"])
        #expect(scan.otherPackages.first?.installs.map(\.workspace) == ["", "web"])
    }
}
