import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Wat een update tegenhoudt (ouder, peer, runtime) en de nieuwste bruikbare versie.
@Suite struct UpdateBlockerTests {
    let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    private func metadata(_ ecosystem: String, _ name: String, _ json: String) throws -> PackageMetadata {
        let decoded = try RegistryMetadata.decode(ecosystem: ecosystem, name: name, data: Data(json.utf8))
        return PackageMetadata(latest: decoded.latest, versions: decoded.versions)
    }

    private func repo(components: [ComponentVersion] = [], packages: [PackageUse], other: [PackageUse] = []) -> RepoVersions {
        RepoVersions(accountId: UUID(), repo: "acme/app", components: components, packages: packages, otherPackages: other)
    }

    private func runtime(_ product: String, _ version: String) -> ComponentVersion {
        ComponentVersion(product: product, label: product, version: version, latest: nil, status: .current, sources: [".nvmrc"])
    }

    private func direct(_ version: String, _ requested: String?, workspace: String = "") -> PackageInstall {
        PackageInstall(version: version, workspace: workspace, scope: .direct, source: "package-lock.json", requested: requested)
    }

    // MARK: - Runtime

    @Test func nodeTooOldBlocksExpressFive() throws {
        let express = PackageUse(ecosystem: "npm", name: "express", installs: [direct("4.21.2", "^4.21.0")])
        let index = ["npm:express": try metadata("npm", "express", RegistryFixtures.npmExpress)]
        let old = UpdateContext(repo: repo(components: [runtime("nodejs", "16")], packages: [express]), metadata: index)
        let update = try #require(express.update(latest: "5.3.0", context: old))
        #expect(update.status == .blockedByRuntime(runtime: "nodejs", needs: ">= 18", installed: "16"))
        #expect(update.status.blocker == .runtime(runtime: "nodejs", needs: ">= 18", installed: "16"))
        #expect(update.step == .major)
        // Geen nieuwere versie draait op Node 16.
        #expect(update.usable == "4.21.2")

        let current = UpdateContext(repo: repo(components: [runtime("nodejs", "20")], packages: [express]), metadata: index)
        let fine = try #require(express.update(latest: "5.3.0", context: current))
        #expect(fine.status == .needsManifestChange)
        #expect(fine.usable == "5.3.0")
    }

    @Test func phpTooOldKeepsMonologOnTwo() throws {
        let monolog = PackageUse(ecosystem: "Packagist", name: "monolog/monolog", installs: [
            PackageInstall(version: "2.10.0", workspace: "", scope: .direct, source: "composer.lock", requested: "^2.9"),
        ])
        let context = UpdateContext(
            repo: repo(components: [runtime("php", "7.4")], packages: [monolog]),
            metadata: ["Packagist:monolog/monolog": try metadata("Packagist", "monolog/monolog", RegistryFixtures.packagistMonolog)]
        )
        let update = try #require(monolog.update(latest: "3.12.1", context: context))
        #expect(update.status == .blockedByRuntime(runtime: "php", needs: ">=8.1", installed: "7.4"))
        #expect(update.usable == "2.11.1")
    }

    @Test func pythonRustAndDotnetRuntimes() throws {
        let requests = PackageUse(ecosystem: "PyPI", name: "requests", installs: [
            PackageInstall(version: "2.31.0", workspace: "", scope: .direct, source: "poetry.lock", requested: ">=2.28"),
        ])
        let python = UpdateContext(repo: repo(components: [runtime("python", "3.8")], packages: [requests]),
                                   metadata: ["PyPI:requests": try metadata("PyPI", "requests", RegistryFixtures.pypiRequests)])
        let blocked = try #require(requests.update(latest: "2.34.2", context: python))
        #expect(blocked.status == .blockedByRuntime(runtime: "python", needs: ">=3.10", installed: "3.8"))
        // 2.32.0 is ingetrokken; 2.32.3 draait op 3.8.
        #expect(blocked.usable == "2.32.3")

        let anyhow = PackageUse(ecosystem: "crates.io", name: "anyhow", installs: [
            PackageInstall(version: "1.0.30", workspace: "", scope: .direct, source: "Cargo.lock", requested: "1.0"),
        ])
        let rust = UpdateContext(repo: repo(components: [runtime("rust", "1.60")], packages: [anyhow]),
                                 metadata: ["crates.io:anyhow": try metadata("crates.io", "anyhow", RegistryFixtures.cratesAnyhow)])
        let crate = try #require(anyhow.update(latest: "1.0.104", context: rust))
        #expect(crate.status == .blockedByRuntime(runtime: "rust", needs: ">= 1.68", installed: "1.60"))
        #expect(crate.usable == "1.0.80")

        let modern = PackageUse(ecosystem: "NuGet", name: "Acme.Modern", installs: [
            PackageInstall(version: "1.0.0", workspace: "", scope: .direct, source: "App.csproj", requested: "1.0.0"),
        ])
        let dotnet = UpdateContext(repo: repo(components: [runtime("dotnet", "8.0")], packages: [modern]),
                                   metadata: ["NuGet:Acme.Modern": try metadata("NuGet", "Acme.Modern", RegistryFixtures.nugetModernOnly)])
        #expect(modern.update(latest: "2.0.0", context: dotnet)?.status == .blockedByRuntime(runtime: "dotnet", needs: ">= 9.0", installed: "8.0"))
    }

    // MARK: - Peers

    @Test func peersBlockReactAndReactDOM() throws {
        let react = PackageUse(ecosystem: "npm", name: "react", installs: [direct("18.3.1", "^18.2.0")])
        let reactDOM = PackageUse(ecosystem: "npm", name: "react-dom", installs: [direct("18.3.1", "^18.2.0")])
        let context = UpdateContext(repo: repo(packages: [react, reactDOM]), metadata: [
            "npm:react": try metadata("npm", "react", RegistryFixtures.npmReact),
            "npm:react-dom": try metadata("npm", "react-dom", RegistryFixtures.npmReactDOM),
        ])
        // react-dom 19 vraagt react ^19.2.0; de workspace heeft react 18.3.1.
        let dom = try #require(reactDOM.update(latest: "19.2.0", context: context))
        #expect(dom.status == .blockedByPeer(name: "react", needs: "^19.2.0", installed: "18.3.1"))
        #expect(dom.usable == "18.3.1")
        // react 19 wordt tegengehouden door react-dom 18 (peer ^18.3.1); vanaf react-dom 19.0.0 mag het.
        let core = try #require(react.update(latest: "19.2.0", context: context))
        #expect(core.status == .blockedByPackage(parent: "react-dom", parentRange: "^18.3.1", minimumParentVersion: "19.0.0"))
        // Een peer in een andere workspace telt niet.
        let elsewhere = UpdateContext(repo: repo(packages: [react, PackageUse(ecosystem: "npm", name: "react-dom", installs: [direct("18.3.1", "^18", workspace: "docs")])]),
                                      metadata: context.metadata)
        #expect(react.update(latest: "19.2.0", context: elsewhere)?.status == .needsManifestChange)
    }

    // MARK: - Ouders

    @Test func parentRangeHoldsATransitiveInstall() throws {
        let express = PackageUse(ecosystem: "npm", name: "express", installs: [direct("4.21.2", "^4.21.0")])
        let qs = PackageUse(ecosystem: "npm", name: "qs", installs: [
            PackageInstall(version: "6.13.0", workspace: "", scope: .transitive, via: ["express"], source: "package-lock.json", requested: "6.13.0"),
        ])
        let context = UpdateContext(repo: repo(packages: [express], other: [qs]),
                                    metadata: ["npm:express": try metadata("npm", "express", RegistryFixtures.npmExpress)])
        // express 4.21.2 vraagt precies qs 6.13.0; pas express 5.3.0 (^6.16.0) laat qs 6.16.0 toe.
        let update = try #require(qs.updates(latest: "6.16.0", context: context).first?.update)
        #expect(update.status == .blockedByPackage(parent: "express", parentRange: "6.13.0", minimumParentVersion: "5.3.0"))
        // Zonder metadata van qs zelf is de nieuwste bruikbare niet te zeggen.
        #expect(update.usable == nil)
        // Geen versie van express laat qs 6.14.1 toe (5.3.0 vraagt ^6.16.0).
        let none = try #require(qs.updates(latest: "6.14.1", context: context).first?.update)
        #expect(none.status == .blockedByPackage(parent: "express", parentRange: "6.13.0", minimumParentVersion: nil))
        // Zonder context is de ouder bekend, zijn minimum niet.
        #expect(qs.updates(latest: "6.16.0").first?.update.status
            == .blockedByPackage(parent: "express", parentRange: "6.13.0", minimumParentVersion: nil))
    }

    @Test func lowestFindsTheParentByBinarySearch() throws {
        var versions: [String: VersionMetadata] = [:]
        for minor in 0..<8 { versions["1.\(minor).0"] = VersionMetadata() }
        // Alleen de nieuwste is bekend: eerst die opvragen.
        versions["1.7.0"] = VersionMetadata(dependencies: ["child": ">= 2.0"])
        let package = PackageMetadata(latest: "1.7.0", versions: versions)
        let context = UpdateContext(index: RegistryIndex(["PyPI:parent": package]), runtimes: [:], installed: [:])
        var asked: [String] = []
        let admits = { (metadata: VersionMetadata) -> Bool? in
            metadata.dependencies.map { VersionRange.parse(ecosystem: "PyPI", name: "child", requested: $0["child"] ?? "")?.contains("2.1") ?? true }
        }
        #expect(context.lowest(after: "1.0.0", of: "PyPI:parent", admits: admits, request: { asked.append($0) }) == "1.7.0")
        #expect(asked == ["1.4.0"])
    }

    // MARK: - Kwetsbaarheden

    @Test func vulnerabilityFixUsesTheSameRules() throws {
        func vulnerability(_ version: String, fixedIn: String, scope: DependencyScope, via: [String] = [], requested: String?) -> Vulnerability {
            Vulnerability(id: "GHSA-x", cve: nil, summary: nil, severity: "HIGH", ecosystem: "npm", package: "qs", version: version,
                          fixedIn: fixedIn, source: "package-lock.json", workspace: "", scope: scope, via: via, requested: requested)
        }
        #expect(vulnerability("6.13.0", fixedIn: "6.13.1", scope: .direct, requested: "^6.13.0").fix == .withinRange(package: "qs", to: "6.13.1"))
        #expect(vulnerability("6.13.0", fixedIn: "7.0.0", scope: .direct, requested: "^6.13.0").fix == .needsManifestChange(package: "qs", to: "7.0.0"))
        #expect(vulnerability("6.13.0", fixedIn: "6.13.1", scope: .direct, requested: nil).fix == .update(package: "qs", to: "6.13.1"))
        #expect(vulnerability("6.13.0", fixedIn: "6.13.1", scope: .transitive, via: ["express"], requested: nil).fix
            == .updateParent(parent: "express", package: "qs", minimum: "6.13.1"))

        let express = PackageUse(ecosystem: "npm", name: "express", installs: [direct("4.21.2", "^4.21.0")])
        let context = UpdateContext(repo: repo(packages: [express]),
                                    metadata: ["npm:express": try metadata("npm", "express", RegistryFixtures.npmExpress)])
        let held = vulnerability("6.13.0", fixedIn: "6.16.0", scope: .transitive, via: ["express"], requested: "6.13.0")
        #expect(held.fix(in: context) == .blocked(package: "qs", to: "6.16.0", by: .package(parent: "express", parentRange: "6.13.0", minimumParentVersion: "5.3.0")))
        #expect(held.fix == .blocked(package: "qs", to: "6.16.0", by: .package(parent: "express", parentRange: "6.13.0", minimumParentVersion: nil)))
    }

    @Test func vulnerabilityFixBlockedByTheRuntime() throws {
        let express = PackageUse(ecosystem: "npm", name: "express", installs: [direct("4.21.2", "^4.21.0")])
        let context = UpdateContext(repo: repo(components: [runtime("nodejs", "16")], packages: [express]),
                                    metadata: ["npm:express": try metadata("npm", "express", RegistryFixtures.npmExpress)])
        let vulnerability = Vulnerability(id: "GHSA-y", cve: nil, summary: nil, severity: "HIGH", ecosystem: "npm", package: "express",
                                          version: "4.21.2", fixedIn: "5.0.0", source: "package-lock.json", workspace: "", scope: .direct,
                                          requested: "^4.21.0")
        #expect(vulnerability.fix(in: context) == .blocked(package: "express", to: "5.0.0", by: .runtime(runtime: "nodejs", needs: ">= 18", installed: "16")))
    }

    // MARK: - Samenvoegen en opslaan

    @Test func combinedWeighsBlockersHighest() {
        let blocked = PackageUpdate(status: .blockedByRuntime(runtime: "nodejs", needs: ">= 18", installed: "16"), step: .major, latest: "5.0.0", usable: "4.21.2")
        let manifest = PackageUpdate(status: .needsManifestChange, step: .major, latest: "5.0.0", usable: "5.0.0")
        let combined = PackageUpdate.combined([manifest, blocked])
        #expect(combined?.status == blocked.status)
        #expect(combined?.usable == "4.21.2")
    }

    @Test func summariesUseTheReportMetadata() throws {
        let express = PackageUse(ecosystem: "npm", name: "express", installs: [direct("4.21.2", "^4.21.0")])
        let report = VersionReport(
            checkedAt: t0,
            repos: [repo(components: [runtime("nodejs", "16")], packages: [express])],
            latestPackages: ["npm:express": PackageLatest(version: "5.3.0", seenAt: t0)],
            packageMetadata: ["npm:express": try metadata("npm", "express", RegistryFixtures.npmExpress)]
        )
        let summary = try #require(report.packageSummaries().first { $0.id == "npm:express" })
        #expect(summary.behind.first?.update?.status == .blockedByRuntime(runtime: "nodejs", needs: ">= 18", installed: "16"))
        #expect(summary.behind.first?.update?.usable == "4.21.2")
    }

    @Test func metadataRoundTripsAndOldFilesDecode() throws {
        let report = VersionReport(checkedAt: t0, repos: [], packageMetadata: [
            "npm:express": try metadata("npm", "express", RegistryFixtures.npmExpress),
            "Go:github.com/spf13/cobra": PackageMetadata(latest: "1.10.2", versions: ["1.10.2": VersionMetadata()], isComplete: false),
        ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(VersionReport.self, from: encoder.encode(report)) == report)

        // versions.json van vóór de blokkades: geen `packageMetadata`, geen `requested` per kwetsbaarheid.
        let old = #"""
        {"checkedAt":"2026-10-01T00:00:00Z","repos":[{"accountId":"00000000-0000-0000-0000-000000000001","repo":"acme/app","components":[],
        "vulnerabilities":[{"id":"GHSA-a","ecosystem":"npm","package":"qs","version":"6.13.0","fixedIn":"6.14.1","source":"package-lock.json"}]}]}
        """#
        let decoded = try decoder.decode(VersionReport.self, from: Data(old.utf8))
        #expect(decoded.packageMetadata.isEmpty)
        #expect(decoded.repos.first?.vulnerabilities.first?.requested == nil)
        #expect(decoded.repos.first?.vulnerabilities.first?.fix == .update(package: "qs", to: "6.14.1"))
    }
}

/// De check haalt op wat de blokkades nodig hebben, en niet meer.
@Suite struct UpdateBlockerCheckTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    /// sinatra 3.2.0 houdt rack op ~> 2.2; rack 3.0.0 lost een lek op. RubyGems geeft de
    /// dependencies per versie apart: de check vraagt alleen de versies die het binair zoeken nodig heeft.
    @Test func findsTheLowestParentWithFewRequestsAndCachesThem() async throws {
        // Gesorteerd: rack@2.2.9, sinatra@3.2.0.
        let documents = [
            ("querybatch", #"{"results":[{"vulns":[{"id":"GHSA-r"}]},{}]}"#),
            ("vulns/GHSA-r", #"{"id":"GHSA-r","aliases":[],"database_specific":{"severity":"HIGH"},"affected":[{"package":{"name":"rack","ecosystem":"RubyGems"},"ranges":[{"events":[{"introduced":"0"},{"fixed":"3.0.0"}]}]}]}"#),
            ("rubygems.org/api/v1/versions/sinatra.json", #"""
            [{"number":"4.1.0","platform":"ruby","prerelease":false,"ruby_version":">= 2.7.8","rubygems_version":">= 0"},
            {"number":"4.0.0","platform":"ruby","prerelease":false,"ruby_version":">= 2.7.8","rubygems_version":">= 0"},
            {"number":"3.2.0","platform":"ruby","prerelease":false,"ruby_version":">= 2.6.0","rubygems_version":">= 0"}]
            """#),
        ]
        let http = MockHTTPClient()
        for (route, body) in documents { http.on(route, body: body) }
        http.on("api/v2/rubygems/sinatra/versions/4.1.0.json", body: #"{"name":"sinatra","version":"4.1.0","dependencies":{"development":[],"runtime":[{"name":"rack","requirements":">= 3.0.0, < 4"},{"name":"mustermann","requirements":"~> 3.0"}]}}"#)
        http.on("api/v2/rubygems/sinatra/versions/4.0.0.json", body: #"{"name":"sinatra","version":"4.0.0","dependencies":{"development":[],"runtime":[{"name":"rack","requirements":">= 3.0.0, < 4"}]}}"#)
        let lock = """
        GEM
          remote: https://rubygems.org/
          specs:
            rack (2.2.9)
            sinatra (3.2.0)
              rack (~> 2.2, >= 2.2.4)

        DEPENDENCIES
          sinatra (~> 3.2)
        """
        let gemfile = "source \"https://rubygems.org\"\ngem \"sinatra\", \"~> 3.2\"\n"
        let provider = FileProvider(repos: ["acme/a"], files: ["acme/a": ["Gemfile": gemfile, "Gemfile.lock": lock]])
        let account = Account(kind: .gitHub, organization: "acme", authMethod: .pat, repoWatch: ["acme/a": .prs])

        let report = await VersionChecker(makeProvider: { _ in provider }, http: http, now: { now }).run(accounts: [account])

        let repo = try #require(report.repos.first)
        let vulnerability = try #require(repo.vulnerabilities.first)
        #expect(vulnerability.requested == "~> 2.2, >= 2.2.4")
        #expect(vulnerability.fix(in: report.updateContext(for: repo))
            == .blocked(package: "rack", to: "3.0.0", by: .package(parent: "sinatra", parentRange: "~> 2.2, >= 2.2.4", minimumParentVersion: "4.0.0")))
        let details = http.requests.filter { $0.url!.absoluteString.contains("api/v2/rubygems") }
        #expect(details.count == 2)
        // Het document van sinatra één keer, rack zelf niet (zijn ouder houdt hem al tegen).
        #expect(http.requests.filter { $0.url!.absoluteString.contains("api/v1/versions/sinatra.json") }.count == 1)
        #expect(http.requests.filter { $0.url!.absoluteString.contains("versions/rack") }.isEmpty)

        // De volgende check heeft de dependencies per versie al.
        let again = MockHTTPClient()
        for (route, body) in documents { again.on(route, body: body) }
        let second = await VersionChecker(makeProvider: { _ in provider }, http: again, now: { now }, metadataCache: report.packageMetadata)
            .run(accounts: [account])
        #expect(again.requests.filter { $0.url!.absoluteString.contains("api/v2/rubygems") }.isEmpty)
        let secondRepo = try #require(second.repos.first)
        #expect(secondRepo.vulnerabilities.first?.fix(in: second.updateContext(for: secondRepo))
            == .blocked(package: "rack", to: "3.0.0", by: .package(parent: "sinatra", parentRange: "~> 2.2, >= 2.2.4", minimumParentVersion: "4.0.0")))
    }

    /// De nieuwste versie van een Go-module vraagt een nieuwere Go: de check haalt de versielijst en
    /// zoekt binair naar de hoogste die nog op de Go van de repo draait.
    @Test func goModuleNeedsNewerGo() async throws {
        let http = MockHTTPClient()
        http.on("querybatch", body: #"{"results":[{}]}"#)
        http.on("acme/lib/@latest", body: #"{"Version":"v1.6.0","Time":"2026-09-01T00:00:00Z"}"#)
        http.on("acme/lib/@v/list", body: "v1.0.0\nv1.1.0\nv1.2.0\nv1.3.0\nv1.4.0\nv1.5.0\nv1.6.0\n")
        let goLines = ["1.0.0": "1.18", "1.1.0": "1.18", "1.2.0": "1.20", "1.3.0": "1.21", "1.4.0": "1.22", "1.5.0": "1.23", "1.6.0": "1.24"]
        for (version, go) in goLines {
            http.on("acme/lib/@v/v\(version).mod", body: "module github.com/acme/lib\n\ngo \(go)\n")
        }
        let gomod = """
        module example.com/app

        go 1.21

        require github.com/acme/lib v1.0.0
        """
        let provider = FileProvider(repos: ["acme/a"], files: ["acme/a": ["go.mod": gomod]])
        let account = Account(kind: .gitHub, organization: "acme", authMethod: .pat, repoWatch: ["acme/a": .prs])

        let report = await VersionChecker(makeProvider: { _ in provider }, http: http, now: { now }).run(accounts: [account])

        let user = try #require(report.packageSummaries().first { $0.id == "Go:github.com/acme/lib" }?.behind.first)
        #expect(user.update?.status == .blockedByRuntime(runtime: "go", needs: ">= 1.24", installed: "1.21"))
        #expect(user.update?.usable == "1.3.0")
        let mods = http.requests.filter { $0.url!.absoluteString.hasSuffix(".mod") }
        // De nieuwste plus binair zoeken in zes versies: hoogstens vier go.mod's.
        #expect(mods.count <= 4)
        #expect(http.requests.filter { $0.url!.absoluteString.hasSuffix("@v/list") }.count == 1)
    }
}
