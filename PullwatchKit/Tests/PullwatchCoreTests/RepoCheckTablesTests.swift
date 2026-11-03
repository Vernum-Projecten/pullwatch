import Foundation
import Testing
@testable import PullwatchCore

/// De tabellen op de repo-pagina: een rij per advies met zijn installs eronder, de filters, de
/// sortering op versie, de packages per workspace en de tellingen bovenaan.
@Suite struct RepoCheckTablesTests {
    let account = UUID()

    private func vuln(
        _ id: String, _ package: String, _ version: String, severity: String? = "HIGH", fixedIn: String? = "4.17.21",
        workspace: String = "", scope: DependencyScope = .direct, kind: DependencyKind = .runtime, via: [String] = [],
        cve: String? = nil
    ) -> Vulnerability {
        Vulnerability(id: id, cve: cve, summary: "Prototype pollution in \(package)", severity: severity, ecosystem: "npm", package: package,
                      version: version, fixedIn: fixedIn, source: workspace.isEmpty ? "package-lock.json" : "\(workspace)/package-lock.json",
                      workspace: workspace, scope: scope, kind: kind, via: via)
    }

    private var repo: RepoVersions {
        RepoVersions(
            accountId: account, repo: "acme/mono",
            components: [
                ComponentVersion(product: "nodejs", label: "Node", version: "16", latest: "22.11.0", status: .eol, sources: [".nvmrc"]),
                ComponentVersion(product: "react", label: "React", version: "18.3.1", latest: nil, status: .unknown, sources: []),
            ],
            vulnerabilities: [
                vuln("GHSA-1", "lodash", "4.17.15", workspace: "packages/api", scope: .transitive, via: ["express"], cve: "CVE-2021-1"),
                vuln("GHSA-1", "lodash", "4.17.20", cve: "CVE-2021-1"),
                vuln("GHSA-2", "qs", "6.10.1", severity: "CRITICAL", fixedIn: "6.10.3", scope: .transitive, via: ["express", "body-parser"]),
                vuln("RUSTSEC-1", "semver", "6.3.0", severity: nil, fixedIn: nil, scope: .transitive, kind: .dev, via: ["jest"]),
            ],
            release: ReleaseVersions(tag: "v1.2.0", components: [], vulnerabilities: [vuln("GHSA-1", "lodash", "4.17.20")])
        )
    }

    @Test func oneRowPerAdvisoryWithItsInstallsUnderneath() throws {
        let rows = repo.vulnerabilityRows()
        #expect(rows.count == 3)
        let lodash = try #require(rows.first { $0.package == "lodash" })
        #expect(lodash.primaryId == "GHSA-1", "het id in zijn eigen database")
        #expect(lodash.identifiers == ["GHSA-1", "CVE-2021-1"])
        #expect(lodash.installedVersions == ["4.17.15", "4.17.20"])
        #expect(lodash.workspaces == ["", "packages/api"])
        #expect(lodash.origin == .direct)
        #expect(lodash.inRelease == true)
        let table = VulnerabilityTableRow(row: lodash)
        #expect(table.children.count == 2)
        #expect(Set(table.children.map(\.id)).count == 2, "elke install een eigen id")
        let qs = try #require(rows.first { $0.package == "qs" })
        #expect(qs.inRelease == false)
        #expect(qs.parent == "express")
        #expect(VulnerabilityTableRow(row: qs).children.isEmpty, "één install: geen rijen eronder")
    }

    @Test func severityAndFixComeFromTheBestSource() throws {
        let advisory = GitHubAdvisory(ghsaId: "GHSA-1", cveId: "CVE-2021-1", summary: nil, severity: "MODERATE", cvss: nil, cwes: [],
                                      url: GitHubAdvisory.pageURL(ghsaId: "GHSA-1"), fetchedAt: Date())
        let low = GitHubAdvisory(ghsaId: "GHSA-9", cveId: nil, summary: nil, severity: "LOW", cvss: nil, cwes: [],
                                 url: GitHubAdvisory.pageURL(ghsaId: "GHSA-9"), fetchedAt: Date())
        let rows = repo.vulnerabilityRows(gitHub: ["GHSA-1": advisory, "RUSTSEC-1": low])
        let lodash = try #require(rows.first { $0.package == "lodash" })
        #expect(lodash.severity == .high, "de ernst van OSV zelf gaat voor GitHubs advies")
        let qs = try #require(rows.first { $0.package == "qs" })
        #expect(qs.severity == .critical)
        let semver = try #require(rows.first { $0.package == "semver" })
        #expect(semver.severity == .low, "zonder ernst in OSV geeft GitHubs advies hem")
        #expect(semver.identifiers.contains("GHSA-9"), "ook het id dat alleen GitHub kent")
        #expect(repo.vulnerabilityRows().first { $0.package == "semver" }?.severity == .unknown)
        #expect(!semver.hasFix)
        #expect(semver.fixedIn == nil)
        #expect(semver.fixes == [.none])
        #expect(semver.origin == .dev)
    }

    @Test func filtersNarrowTheTable() {
        let rows = repo.vulnerabilityRows()
        func packages(_ filter: VulnerabilityFilter, text: String = "") -> Set<String> {
            Set(rows.filter { filter.matches($0, text: text) }.map(\.package))
        }
        #expect(packages(VulnerabilityFilter()) == ["lodash", "qs", "semver"])
        #expect(packages(VulnerabilityFilter(severities: [.critical])) == ["qs"])
        #expect(packages(VulnerabilityFilter(origins: [.transitive])) == ["qs"])
        #expect(packages(VulnerabilityFilter(origins: [.dev])) == ["semver"])
        #expect(packages(VulnerabilityFilter(onlyWithFix: true)) == ["lodash", "qs"])
        #expect(packages(VulnerabilityFilter(onlyInRelease: true)) == ["lodash"])
        #expect(packages(VulnerabilityFilter(), text: "body-parser") == ["qs"], "zoekt ook in de keten")
        #expect(packages(VulnerabilityFilter(), text: "cve-2021") == ["lodash"], "zoekt ook in de aliassen")
        #expect(!VulnerabilityFilter().isActive)
        #expect(VulnerabilityFilter(onlyWithFix: true).isActive)
    }

    @Test func versionsSortAsNumbers() {
        #expect(VersionSortKey("4.17.9") < VersionSortKey("4.17.15"))
        #expect(VersionSortKey("10.0") > VersionSortKey("9.9"))
        #expect(VersionSortKey("1.0") < VersionSortKey(nil), "zonder versie achteraan")
        #expect(!(VersionSortKey(nil) < VersionSortKey(nil)))
    }

    @Test func packagesPerWorkspaceWithStatus() throws {
        let repo = RepoVersions(accountId: account, repo: "acme/mono", components: [], packages: [
            PackageUse(ecosystem: "npm", name: "lodash", installs: [
                PackageInstall(version: "4.17.20", workspace: "", scope: .direct, source: "package-lock.json", requested: "^4.17.20"),
                PackageInstall(version: "4.17.15", workspace: "", scope: .transitive, via: ["body-parser"], source: "package-lock.json"),
                PackageInstall(version: "4.17.21", workspace: "packages/web", scope: .direct, source: "packages/web/package-lock.json",
                               requested: "4.17.21"),
            ]),
            PackageUse(ecosystem: "npm", name: "express", installs: [
                PackageInstall(version: "4.18.0", workspace: "", scope: .direct, source: "package-lock.json", requested: "^4.18.0"),
            ]),
        ], otherPackages: [
            PackageUse(ecosystem: "npm", name: "jest", installs: [
                PackageInstall(version: "29.7.0", workspace: "", scope: .direct, kind: .dev, source: "package-lock.json", requested: "^29.7.0"),
            ]),
        ])
        let latest = ["npm:lodash": "4.17.21", "npm:express": "5.1.0"]
        let groups = repo.packageGroups(latest: { latest[$0] })
        #expect(groups.map(\.workspace) == ["", "packages/web"])
        let root = try #require(groups.first)
        let lodash = try #require(root.rows.first { $0.name == "lodash" })
        #expect(lodash.category == .canUpdateNow, "de directe install bepaalt de status")
        #expect(lodash.installedVersions == ["4.17.15", "4.17.20"])
        #expect(RepoPackageTableRow(row: lodash).children.count == 2)
        let express = try #require(root.rows.first { $0.name == "express" })
        #expect(express.category == .needsManifestChange)
        let jest = try #require(root.rows.first { $0.name == "jest" })
        #expect(jest.origin == .dev)
        #expect(jest.category == nil, "geen nieuwste versie bekend")
        let web = try #require(groups.last?.rows.first)
        #expect(web.category == .upToDate)

        #expect(PackageFilter(status: .hasUpdate).matches(lodash))
        #expect(!PackageFilter(status: .hasUpdate).matches(web))
        #expect(PackageFilter(status: .category(.needsManifestChange)).matches(express))
        #expect(!PackageFilter(origins: [.dev]).matches(express))
        #expect(PackageFilter().matches(lodash, text: "body"), "zoekt ook in de keten")

        let summary = RepoCheckSummary(versions: repo, packages: groups)
        #expect(summary.canUpdate == 1)
        #expect(summary.blocked == 0)
    }

    @Test func summaryCountsWhatThePageShows() {
        let summary = RepoCheckSummary(versions: repo, packages: [])
        #expect(summary.vulnerabilities == 3)
        #expect(summary.outdated == 1, "alleen achter of EOL; onbekend telt niet")
        #expect(summary.comparedWith == "v1.2.0")
        #expect(summary.securityFindings == 0)
    }
}
