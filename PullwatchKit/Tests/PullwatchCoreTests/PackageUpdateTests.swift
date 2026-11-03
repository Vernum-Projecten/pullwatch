import Foundation
import Testing
@testable import PullwatchCore

/// Update-status v1: uit installs, gevraagd bereik en de nieuwste versie in het register.
@Suite struct PackageUpdateTests {
    let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    private func status(_ ecosystem: String, _ installed: String, _ requested: String?, latest: String?, name: String = "x") -> PackageUpdate {
        PackageUpdate(ecosystem: ecosystem, name: name, installed: installed, requested: requested, latest: latest)
    }

    @Test func examplesFromTheEpic() {
        let lodash = status("npm", "4.17.15", "^4.17.0", latest: "4.17.21")
        #expect(lodash.status == .withinRange)
        #expect(lodash.step == .patch)
        let react = status("npm", "18.3.1", "^18.2.0", latest: "19.1.0")
        #expect(react.status == .needsManifestChange)
        #expect(react.step == .major)
    }

    @Test func everyStatus() {
        #expect(status("npm", "4.17.21", "^4.17.0", latest: "4.17.21").status == .upToDate)
        #expect(status("npm", "5.0.0", "^5", latest: "4.17.21").status == .upToDate)
        #expect(status("npm", "4.17.21", "^4.17.0", latest: "4.17.21").step == nil)
        #expect(status("npm", "4.17.15", "^4.17.0", latest: nil).status == .unknown)
        #expect(status("npm", "4.17.15", nil, latest: "4.18.0") == PackageUpdate(status: .unknown, step: .minor, latest: "4.18.0"))
        #expect(status("npm", "4.17.15", "latest", latest: "4.18.0").status == .unknown)
        #expect(status("npm", "nightly", "^1", latest: "4.18.0").status == .unknown)
    }

    @Test func perEcosystem() {
        #expect(status("Packagist", "11.9.2", "^11.0", latest: "11.30.0").status == .withinRange)
        #expect(status("PyPI", "2.31.0", ">=2.28,<3", latest: "2.32.3").status == .withinRange)
        #expect(status("PyPI", "4.2.0", "~=4.2.0", latest: "5.1.2").status == .needsManifestChange)
        #expect(status("crates.io", "0.11.0", "0.11", latest: "0.12.0").status == .needsManifestChange)
        #expect(status("NuGet", "13.0.1", "[13.0.1, )", latest: "13.0.3").status == .withinRange)
        #expect(status("RubyGems", "7.1.4", "~> 7.1.4", latest: "7.2.1").status == .needsManifestChange)
        #expect(status("Go", "1.2.3", "v1.2.3", latest: "1.9.0", name: "github.com/a/b").status == .withinRange)
        #expect(status("Go", "1.2.3", "v1.2.3", latest: "2.0.0", name: "github.com/a/b").status == .needsManifestChange)
        #expect(status("SwiftURL", "2.65.0", #"from: "2.60.0""#, latest: "2.70.0").status == .withinRange)
    }

    @Test func combinedTakesTheMostWorkAndTheLargestStep() {
        let within = PackageUpdate(status: .withinRange, step: .patch, latest: "2.0.0")
        let manifest = PackageUpdate(status: .needsManifestChange, step: .major, latest: "2.0.0")
        let current = PackageUpdate(status: .upToDate, step: nil, latest: "2.0.0")
        #expect(PackageUpdate.combined([within, manifest, current]) == PackageUpdate(status: .needsManifestChange, step: .major, latest: "2.0.0"))
        #expect(PackageUpdate.combined([current, within])?.status == .withinRange)
        #expect(PackageUpdate.combined([]) == nil)
    }

    @Test func packageUseGivesEveryInstallItsStatus() {
        let use = PackageUse(ecosystem: "npm", name: "lodash", installs: [
            PackageInstall(version: "4.17.15", workspace: "", scope: .direct, source: "package-lock.json", requested: "^4.17.0"),
            PackageInstall(version: "3.10.1", workspace: "", scope: .transitive, via: ["legacy"], source: "package-lock.json", requested: "^3.10.0"),
        ])
        let updates = use.updates(latest: "4.17.21")
        // De transitieve install valt buiten het bereik van zijn ouder: die houdt hem tegen (#84).
        #expect(updates.map(\.update.status) == [
            .withinRange, .blockedByPackage(parent: "legacy", parentRange: "^3.10.0", minimumParentVersion: nil),
        ])
        #expect(updates.map(\.update.step) == [.patch, .major])
        // De repo zelf: alleen de directe install.
        #expect(use.update(latest: "4.17.21")?.status == .withinRange)
    }

    @Test func summariesCarryTheStatusPerUser() throws {
        let account = UUID()
        let install = PackageInstall(version: "18.3.1", workspace: "", scope: .direct, source: "package-lock.json", requested: "^18.2.0")
        let transitive = PackageInstall(version: "18.3.1", workspace: "", scope: .transitive, via: ["next"], source: "package-lock.json", requested: "^18.2.0")
        let report = VersionReport(checkedAt: t0, repos: [
            RepoVersions(accountId: account, repo: "acme/web", components: [], packages: [PackageUse(ecosystem: "npm", name: "react", installs: [install])]),
            RepoVersions(accountId: account, repo: "acme/docs", components: [], packages: [PackageUse(ecosystem: "npm", name: "react", installs: [install])]),
            RepoVersions(accountId: account, repo: "acme/site", components: [], packages: [],
                         otherPackages: [PackageUse(ecosystem: "npm", name: "react", installs: [transitive])]),
        ], latestPackages: ["npm:react": PackageLatest(version: "19.1.0", seenAt: t0)])
        let summary = try #require(report.packageSummaries().first { $0.id == "npm:react" })
        #expect(summary.behind.map { $0.update?.status } == [.needsManifestChange, .needsManifestChange])
        #expect(summary.behind.first?.updates.map(\.install) == [install])
        #expect(summary.behind.first?.update?.step == .major)
        #expect(summary.transitiveOnly.first?.update?.status == .blockedByPackage(parent: "next", parentRange: "^18.2.0", minimumParentVersion: nil))
    }

    @Test func runtimesHaveNoUpdateStatus() {
        #expect(PackageUser(repoId: "a", repo: "a", version: "1.27.3", sources: ["go.mod"]).update == nil)
    }
}
