import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Provider met vaste repo's en bestanden; `repos == nil` laat `listRepos` falen.
/// Bestanden op een tag staan onder "repo@tag".
private actor FileProvider: PRProvider {
    let repos: [String]?
    let files: [String: [String: String]]
    let brokenRepos: Set<String>
    let tagNames: [String: [String]]
    /// Pad → fout bij het lezen van dat bestand.
    let failingFiles: [String: ProviderError]

    init(
        repos: [String]?, files: [String: [String: String]], brokenRepos: Set<String> = [],
        tags: [String: [String]] = [:], failingFiles: [String: ProviderError] = [:]
    ) {
        self.repos = repos
        self.files = files
        self.brokenRepos = brokenRepos
        self.tagNames = tags
        self.failingFiles = failingFiles
    }

    func currentUserId() async throws -> String { "me" }
    func testConnection() async throws -> String { "me" }
    func listRepos() async throws -> [String] {
        guard let repos else { throw ProviderError.unauthorized }
        return repos
    }
    func openPullRequests() async throws -> [PullRequest] { [] }
    func pullRequests(updatedSince since: Date?, limit: Int) async throws -> [PullRequest] { [] }
    func tags(in repos: [String]) async throws -> TagFetch {
        TagFetch(tags: repos.flatMap { repo in
            (tagNames[repo] ?? []).map { Tag(accountId: UUID(), repo: repo, name: $0, authorName: nil, webURL: URL(string: "https://x")!) }
        })
    }
    func filePaths(in repo: String, ref: String?) async throws -> [String] {
        let key = ref.map { "\(repo)@\($0)" } ?? repo
        if brokenRepos.contains(key) { throw ProviderError.server(status: 500) }
        return (files[key] ?? [:]).keys.sorted()
    }
    func fileContent(in repo: String, path: String, ref: String?) async throws -> String {
        if let error = failingFiles[path] { throw error }
        return files[ref.map { "\(repo)@\($0)" } ?? repo]?[path] ?? ""
    }
    func invalidateCredentials() async {}
}

@Suite struct VersionCheckerTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    func goReleases() -> String {
        #"""
        {"result":{"releases":[
          {"name":"1.27","releaseDate":"2026-08-19","isEol":false,"latest":{"name":"1.27.3"}},
          {"name":"1.26","releaseDate":"2026-02-10","isEol":false,"latest":{"name":"1.26.10"}},
          {"name":"1.25","releaseDate":"2025-08-12","isEol":true,"latest":{"name":"1.25.9"}}
        ]}}
        """#
    }

    func account(_ watch: [String: WatchSet], default fallback: NewRepoDefault = .none) -> Account {
        Account(kind: .gitHub, organization: "acme", authMethod: .pat, repoWatch: watch, newRepoDefault: fallback)
    }

    @Test func checksOnlyFollowedReposAndSortsWorstFirst() async {
        let http = MockHTTPClient()
        http.on("products/go", body: goReleases())
        let provider = FileProvider(
            repos: ["acme/new", "acme/old", "acme/skip", "acme/tagsonly"],
            files: [
                "acme/new": ["go.mod": "go 1.27.1"],
                "acme/old": ["go.mod": "go 1.26", "tools/go.mod": "go 1.25.0", "node_modules/x/go.mod": "go 1.1"],
                "acme/skip": ["go.mod": "go 1.25"],
                "acme/tagsonly": [:],
            ]
        )
        let acc = account(["acme/new": .prs, "acme/old": WatchSet(prs: false, tags: false, completed: true), "acme/tagsonly": .tags])
        let checker = VersionChecker(makeProvider: { _ in provider }, http: http, now: { now })

        let report = await checker.run(accounts: [acc])

        #expect(report.repos.map(\.repo) == ["acme/old", "acme/new", "acme/tagsonly"])
        let old = report.repos[0].components
        #expect(old.count == 1)
        #expect(old[0].version == "1.25.0")
        #expect(old[0].status == .eol)
        #expect(old[0].latest == "1.27.3")
        #expect(old[0].sources == ["go.mod", "tools/go.mod"])
        #expect(report.repos[1].components.first?.status == .current)
        #expect(report.repos[2].components.isEmpty)
        #expect(http.requests.filter { $0.url!.absoluteString.contains("products/go") }.count == 1)
    }

    @Test func componentKeepsLatestPatchOfItsOwnCycle() async {
        let http = MockHTTPClient()
        http.on("products/go", body: goReleases())
        let provider = FileProvider(repos: ["acme/a"], files: ["acme/a": ["go.mod": "go 1.26.9"]])
        let report = await VersionChecker(makeProvider: { _ in provider }, http: http, now: { now })
            .run(accounts: [account(["acme/a": .prs])])
        let go = report.repos.first?.components.first
        #expect(go?.cycle == "1.26")
        #expect(go?.cycleLatest == "1.26.10")
        #expect(go?.latest == "1.27.3")
    }

    @Test func cycleMatchesLongestPrefix() throws {
        let releases = [
            EndOfLifeRelease(name: "1.27", releaseDate: "2026-08-19", isEol: false, latest: "1.27.4"),
            EndOfLifeRelease(name: "1.2", releaseDate: "2014-01-01", isEol: true, latest: "1.2.2"),
        ]
        #expect(EndOfLife.cycle(of: "1.27.3", releases: releases)?.latest == "1.27.4")
        #expect(EndOfLife.cycle(of: "1.2.1", releases: releases)?.name == "1.2")
        #expect(EndOfLife.cycle(of: "1.28", releases: releases) == nil)
    }

    @Test func oldComponentWithoutCycleDecodes() throws {
        let json = #"{"product":"go","label":"Go","version":"1.26","status":"current","sources":[]}"#
        let component = try JSONDecoder().decode(ComponentVersion.self, from: Data(json.utf8))
        #expect(component.cycleLatest == nil)
    }

    @Test func collectsDirectPackagesAndTheirLatestVersions() async {
        let http = MockHTTPClient()
        http.on("querybatch", body: #"{"results":[{},{},{}]}"#)
        http.on("proxy.golang.org/github.com/x/direct/@latest", body: #"{"Version":"v1.3.0"}"#)
        http.on("proxy.golang.org/github.com/acme/private/@latest", status: 404, body: "")
        let gomod = """
        module example.com/app
        require (
            github.com/x/direct v1.2.0
            github.com/acme/private v0.1.0
            github.com/x/indirect v0.9.0 // indirect
        )
        """
        let provider = FileProvider(repos: ["acme/a"], files: ["acme/a": ["go.mod": gomod]])

        let report = await VersionChecker(makeProvider: { _ in provider }, http: http, now: { now })
            .run(accounts: [account(["acme/a": .prs])])

        #expect(report.repos.first?.packages.map(\.name) == ["github.com/x/direct", "github.com/acme/private"])
        #expect(report.latestPackages["Go:github.com/x/direct"] == PackageLatest(version: "1.3.0", seenAt: now))
        #expect(report.latestPackages["Go:github.com/acme/private"] == PackageLatest(version: nil, seenAt: now))
        #expect(report.latestPackages["Go:github.com/x/indirect"] == nil)
        #expect(http.requests.filter { $0.url!.absoluteString.contains("x/indirect") }.isEmpty)
    }

    @Test func replacingAddsARepoThatWasNotCheckedYet() {
        let id = UUID()
        let old = VersionReport(checkedAt: now, repos: [RepoVersions(accountId: id, repo: "a/one", components: [])])
        let updated = old.replacing(RepoVersions(accountId: id, repo: "a/new", components: []))
        #expect(Set(updated.repos.map(\.repo)) == ["a/one", "a/new"])
    }

    @Test func replacingMergesLatestAndKeepsSeenDate() {
        let id = UUID()
        let old = VersionReport(checkedAt: now, repos: [RepoVersions(accountId: id, repo: "a/one", components: [])], latestPackages: [
            "npm:react": PackageLatest(version: "19.3.0", seenAt: now),
            "npm:vite": PackageLatest(version: "6.0.0", seenAt: now),
        ])
        let later = now + 3600
        let updated = old.replacing(RepoVersions(accountId: id, repo: "a/one", components: []), latest: [
            "npm:react": PackageLatest(version: "19.3.0", seenAt: later),
            "npm:zod": PackageLatest(version: "3.1.0", seenAt: later),
        ])
        #expect(updated.latestPackages["npm:react"]?.seenAt == now)
        #expect(updated.latestPackages["npm:vite"]?.version == "6.0.0")
        #expect(updated.latestPackages["npm:zod"]?.seenAt == later)
        let failed = updated.replacing(RepoVersions(accountId: id, repo: "a/one", components: []), latest: [
            "npm:react": PackageLatest(version: nil, seenAt: later),
        ])
        #expect(failed.latestPackages["npm:react"] == PackageLatest(version: "19.3.0", seenAt: now))
    }

    @Test func followsReposViaNewRepoDefault() async {
        let provider = FileProvider(repos: ["acme/a"], files: [:])
        let report = await VersionChecker(makeProvider: { _ in provider }, http: MockHTTPClient(), now: { now })
            .run(accounts: [account([:], default: .prs)])
        #expect(report.repos.map(\.repo) == ["acme/a"])
    }

    @Test func runMissingChecksOnlyNewlyFollowedRepos() async {
        let provider = FileProvider(repos: ["acme/known", "acme/new", "acme/off"], files: [:])
        let followed = account(["acme/off": .none], default: .prsAndTags)
        let checker = VersionChecker(makeProvider: { _ in provider }, http: MockHTTPClient(), now: { now })
        let report = VersionReport(checkedAt: now, repos: [RepoVersions(accountId: followed.id, repo: "Acme/Known", components: [])])

        let fresh = await checker.runMissing(accounts: [followed], in: report)
        #expect(fresh.repos.map(\.repo) == ["acme/new"])

        let merged = report.replacing(fresh.repos, latest: fresh.latest)
        #expect(Set(merged.repos.map(\.repo)) == ["Acme/Known", "acme/new"])
        #expect(merged.checkedAt == now)
        #expect(await checker.runMissing(accounts: [followed], in: merged).repos.isEmpty)
    }

    @Test func errorsStayPerRepoAndPerAccount() async {
        let http = MockHTTPClient()
        let good = FileProvider(repos: ["acme/ok", "acme/broken"], files: ["acme/ok": [:]], brokenRepos: ["acme/broken"])
        let failing = FileProvider(repos: nil, files: [:])
        let first = account(["acme/ok": .prs, "acme/broken": .prs])
        let second = Account(kind: .gitHub, organization: "kapot", authMethod: .pat)
        let checker = VersionChecker(makeProvider: { $0.id == first.id ? good : failing }, http: http, now: { now })

        let report = await checker.run(accounts: [first, second])

        let byRepo = Dictionary(uniqueKeysWithValues: report.repos.map { ($0.repo, $0) })
        #expect(byRepo["acme/ok"]?.error == nil)
        #expect(byRepo["acme/broken"]?.error == ProviderError.server(status: 500).userMessage)
        #expect(byRepo[second.displayName]?.error == ProviderError.unauthorized.userMessage)
    }

    @Test func unknownWhenReleasesUnavailable() async {
        let http = MockHTTPClient()
        http.on("products/go", status: 500, body: "")
        let provider = FileProvider(repos: ["acme/a"], files: ["acme/a": ["go.mod": "go 1.26"]])
        let report = await VersionChecker(makeProvider: { _ in provider }, http: http, now: { now })
            .run(accounts: [account(["acme/a": .prs])])
        #expect(report.repos.first?.components.first?.status == .unknown)
    }

    @Test func comparesVersionsNumerically() {
        #expect(VersionChecker.isOlder("1.9", than: "1.10"))
        #expect(!VersionChecker.isOlder("1.10", than: "1.9"))
        #expect(!VersionChecker.isOlder("8.0", than: "8"))
    }
}

@Suite struct VersionCheckerVulnerabilityTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    func account() -> Account {
        Account(kind: .gitHub, organization: "acme", authMethod: .pat, repoWatch: ["acme/a": .prs, "acme/b": .prs])
    }

    @Test func attachesVulnerabilitiesPerRepoWithOneSharedQuery() async {
        let http = MockHTTPClient()
        http.on("querybatch", body: #"{"results":[{"vulns":[{"id":"GHSA-a"}]}]}"#)
        http.on("vulns/GHSA-a", body: #"{"id":"GHSA-a","summary":"lek","database_specific":{"severity":"HIGH"},"affected":[{"package":{"name":"lodash","ecosystem":"npm"},"ranges":[{"events":[{"fixed":"4.17.21"}]}]}]}"#)
        let lock = #"{"lockfileVersion":3,"packages":{"node_modules/lodash":{"version":"4.17.20"}}}"#
        let provider = FileProvider(repos: ["acme/a", "acme/b"], files: [
            "acme/a": ["package-lock.json": lock],
            "acme/b": ["web/package-lock.json": lock, "package.json": "{}"],
        ])

        let report = await VersionChecker(makeProvider: { _ in provider }, http: http, now: { now }).run(accounts: [account()])

        #expect(report.repos.count == 2)
        for repo in report.repos {
            #expect(repo.vulnerabilities.map(\.id) == ["GHSA-a"])
            #expect(repo.vulnerabilities.first?.fixedIn == "4.17.21")
            #expect(repo.severity == VersionStatus.eol.severity)
        }
        #expect(http.requests.filter { $0.url!.absoluteString.contains("querybatch") }.count == 1)
    }

    @Test func osvFailureIsReportedButVersionsRemain() async {
        let http = MockHTTPClient()
        http.on("querybatch", status: 500, body: "")
        let provider = FileProvider(repos: ["acme/a"], files: ["acme/a": ["go.mod": "go 1.26\nrequire x.com/y v1.0.0\n"]])

        let report = await VersionChecker(makeProvider: { _ in provider }, http: http, now: { now }).run(accounts: [account()])

        let repo = report.repos.first
        #expect(repo?.components.first?.label == "Go")
        #expect(repo?.vulnerabilities.isEmpty == true)
        #expect(repo?.vulnerabilityError?.isEmpty == false)
    }

    @Test func oldReportWithoutVulnerabilitiesDecodes() throws {
        let json = #"{"accountId":"00000000-0000-0000-0000-000000000001","repo":"acme/a","components":[]}"#
        let repo = try JSONDecoder().decode(RepoVersions.self, from: Data(json.utf8))
        #expect(repo.vulnerabilities.isEmpty)
        #expect(repo.vulnerabilityError == nil)
    }
}

@Suite struct LockedFrameworkVersionTests {
    @Test func lockfileVersionWinsOverManifestMinimum() async {
        let http = MockHTTPClient()
        http.on("products/symfony", body: #"{"result":{"releases":[{"name":"7.4","releaseDate":"2025-11-01","isEol":false,"latest":{"name":"7.4.9"}},{"name":"7.2","releaseDate":"2024-11-01","isEol":true,"latest":{"name":"7.2.9"}}]}}"#)
        http.on("querybatch", body: #"{"results":[{}]}"#)
        let provider = FileProvider(repos: ["p/api"], files: ["p/api": [
            "composer.json": #"{"require":{"symfony/console":"^7.2"}}"#,
            "composer.lock": #"{"packages":[{"name":"symfony/console","version":"v7.4.8"}]}"#,
        ]])
        let account = Account(kind: .azureDevOps, organization: "x", authMethod: .pat, repoWatch: ["p/api": .prs])

        let report = await VersionChecker(makeProvider: { _ in provider }, http: http, now: { Date(timeIntervalSince1970: 1_792_000_000) })
            .run(accounts: [account])

        let symfony = report.repos.first?.components.first
        #expect(symfony?.version == "7.4.8")
        #expect(symfony?.status == .current)
        #expect(symfony?.sources == ["composer.lock"])
    }
}

@Suite struct RustPinnedVersionTests {
    @Test func toolchainWinsOverCargoMinimum() async {
        let http = MockHTTPClient()
        http.on("products/rust", body: #"{"result":{"releases":[{"name":"1.99","releaseDate":"2026-09-01","isEol":false,"latest":{"name":"1.99.1"}}]}}"#)
        let provider = FileProvider(repos: ["f/ehr"], files: ["f/ehr": [
            "Cargo.toml": "[workspace.package]\nrust-version = \"1.98\"\n",
            "rust-toolchain.toml": "[toolchain]\nchannel = \"1.99.1\"\n",
        ]])
        let account = Account(kind: .gitHub, organization: "f", authMethod: .pat, repoWatch: ["f/ehr": .prs])

        let report = await VersionChecker(makeProvider: { _ in provider }, http: http, now: { Date(timeIntervalSince1970: 1_792_000_000) })
            .run(accounts: [account])

        let rust = report.repos.first?.components.first
        #expect(rust?.version == "1.99.1")
        #expect(rust?.sources == ["rust-toolchain.toml"])
    }
}

@Suite struct PinnedOverMinimumTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    func run(_ files: [String: String]) async -> [ComponentVersion] {
        let provider = FileProvider(repos: ["t/go-tool"], files: ["t/go-tool": files])
        let account = Account(kind: .azureDevOps, organization: "t", authMethod: .pat, repoWatch: ["t/go-tool": .prs])
        let report = await VersionChecker(makeProvider: { _ in provider }, http: MockHTTPClient(), now: { now }).run(accounts: [account])
        return report.repos.first?.components ?? []
    }

    @Test func locallyReplacedGoModuleDoesNotCount() async {
        let components = await run([
            "backend/go.mod": "module app\n\ngo 1.27.2\n\nreplace github.com/x/bot => ./internal/bot\n",
            "backend/internal/bot/go.mod": "module github.com/x/bot\n\ngo 1.21\n",
            "tools/go.mod": "module tools\n\ngo 1.26\n",
        ])
        let go = components.first { $0.label == "Go" }
        #expect(go?.version == "1.26")
        #expect(go?.sources == ["backend/go.mod", "tools/go.mod"])
    }

    @Test func nodeEngineMinimumDropsWhenDockerPinsNode() async {
        let components = await run([
            "teams-app/package.json": #"{"engines":{"node":">=20.0.0"}}"#,
            "docker/Dockerfile.frontend": "FROM node:24-alpine\n",
        ])
        #expect(components.map(\.label) == ["Docker node"])
    }

    @Test func minimumStaysWithoutPin() async {
        let components = await run(["package.json": #"{"engines":{"node":">=20.0.0"}}"#])
        #expect(components.map { "\($0.label)@\($0.version)" } == ["Node@20.0.0"])
    }

    @Test func resolvesRelativeReplacePaths() {
        #expect(StackDetector.localGoReplacements(path: "backend/go.mod", content: "replace a => ./internal/a\nreplace (\n  b v1 => ../shared/b\n  c => github.com/c v1.0.0\n)\n")
            == ["backend/internal/a", "shared/b"])
    }
}

@Suite struct SingleRepoRefreshTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    @Test func checksOneRepoAndReplacesItKeepingCheckedAt() async {
        let http = MockHTTPClient()
        http.on("products/go", body: #"{"result":{"releases":[{"name":"1.27","releaseDate":"2026-08-19","isEol":false,"latest":{"name":"1.27.3"}}]}}"#)
        let provider = FileProvider(repos: nil, files: ["a/one": ["go.mod": "go 1.27.2"]])
        let account = Account(kind: .gitHub, organization: "a", authMethod: .pat, repoWatch: ["a/one": .prs])

        let (fresh, latest) = await VersionChecker(makeProvider: { _ in provider }, http: http, now: { now }).run(account: account, repo: "a/one")

        #expect(fresh.components.first?.status == .current)
        #expect(latest.isEmpty)
        let old = VersionReport(checkedAt: Date(timeIntervalSince1970: 1), repos: [
            RepoVersions(accountId: account.id, repo: "a/one", components: [], error: "Netwerkfout"),
            RepoVersions(accountId: account.id, repo: "a/two", components: []),
        ])
        let updated = old.replacing(fresh, latest: latest)
        #expect(updated.checkedAt == old.checkedAt)
        #expect(updated.repos.first { $0.repo == "a/one" }?.error == nil)
        #expect(updated.repos.count == 2)
    }
}

@Suite struct LatestReleaseTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    @Test func picksHighestFinalVersionTag() {
        #expect(VersionChecker.latestTag(["v1.9.0", "v1.10.0", "v2.0.0-rc1", "nightly", "release-1.2"]) == "v1.10.0")
        #expect(VersionChecker.latestTag(["v2.0.0-rc1", "v2.0.0-rc2"]) == "v2.0.0-rc2")
        #expect(VersionChecker.latestTag(["nightly"]) == nil)
        #expect(VersionChecker.latestTag([]) == nil)
    }

    @Test func fixedOnMainIsNotReported() async {
        let http = MockHTTPClient()
        http.on("products/go", body: #"{"result":{"releases":[{"name":"1.27","releaseDate":"2026-08-19","isEol":false,"latest":{"name":"1.27.3"}},{"name":"1.26","releaseDate":"2026-02-10","isEol":true,"latest":{"name":"1.26.10"}}]}}"#)
        // Alleen de release heeft het (kwetsbare) pakket nog.
        http.on("querybatch", body: #"{"results":[{"vulns":[{"id":"GO-1"}]}]}"#)
        http.on("vulns/GO-1", body: #"{"id":"GO-1","affected":[{"package":{"name":"x.com/y","ecosystem":"Go"},"ranges":[{"events":[{"fixed":"1.1.0"}]}]}]}"#)
        let provider = FileProvider(
            repos: ["a/one"],
            files: [
                "a/one": ["go.mod": "go 1.27.2\n"],
                "a/one@v1.0.0": ["go.mod": "go 1.26\nrequire x.com/y v1.0.0\n"],
            ],
            tags: ["a/one": ["v0.9.0", "v1.0.0"]]
        )
        let account = Account(kind: .gitHub, organization: "a", authMethod: .pat, repoWatch: ["a/one": .prs])

        let repo = await VersionChecker(makeProvider: { _ in provider }, http: http, now: { now }).run(account: account, repo: "a/one").repo

        #expect(repo.components.first?.status == .current)
        #expect(repo.release?.tag == "v1.0.0")
        #expect(repo.release?.components.first?.version == "1.26")
        #expect(repo.release?.components.first?.status == .eol)
        #expect(repo.release?.vulnerabilities.first?.fixedIn == "1.1.0")
        // Op main opgelost: telt niet mee.
        #expect(repo.worstStatus == .current)
        #expect(repo.vulnerabilities.isEmpty)
        #expect(repo.severity == VersionStatus.current.severity)
    }

    @Test func noTagsMeansNoRelease() async {
        let provider = FileProvider(repos: ["a/one"], files: ["a/one": [:]])
        let account = Account(kind: .gitHub, organization: "a", authMethod: .pat, repoWatch: ["a/one": .prs])

        let repo = await VersionChecker(makeProvider: { _ in provider }, http: MockHTTPClient(), now: { now }).run(account: account, repo: "a/one").repo

        #expect(repo.release == nil)
    }

    @Test func releaseOnlyVulnerabilityIsNotNotified() {
        let id = UUID()
        func vuln(_ v: String) -> Vulnerability {
            Vulnerability(id: "GO-1", cve: nil, summary: nil, severity: nil, ecosystem: "Go", package: "x", version: v, fixedIn: nil, source: "go.mod")
        }
        let before = VersionReport(checkedAt: now, repos: [RepoVersions(accountId: id, repo: "a/one", components: [])])
        let after = VersionReport(checkedAt: now, repos: [RepoVersions(
            accountId: id, repo: "a/one", components: [],
            release: ReleaseVersions(tag: "v1", components: [], vulnerabilities: [vuln("1.0.0")])
        )])
        #expect(after.newVulnerabilities(since: before).isEmpty)
        #expect(after.repos[0].isInRelease(vuln("1.0.0")) == true)
    }
}

@Suite struct ScanFailureTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)
    let account = Account(kind: .gitHub, organization: "a", authMethod: .pat, repoWatch: ["a/one": .prs])

    func check(_ failure: ProviderError, http: MockHTTPClient = MockHTTPClient()) async -> RepoVersions {
        let provider = FileProvider(
            repos: ["a/one"],
            files: ["a/one": ["go.mod": "go 1.27\n", "package-lock.json": "{}"]],
            failingFiles: ["package-lock.json": failure]
        )
        return await VersionChecker(makeProvider: { _ in provider }, http: http, now: { now }).run(account: account, repo: "a/one").repo
    }

    @Test func vanishedFileIsSkipped() async {
        #expect(await check(.server(status: 404)).error == nil)
    }

    @Test func rateLimitedReadFailsTheRepoInsteadOfHidingCVEs() async {
        #expect(await check(.rateLimited(until: now)).error != nil)
    }

    @Test func missingOSVDetailsMarkTheCheckIncomplete() async {
        let http = MockHTTPClient()
        http.on("querybatch", body: #"{"results":[{"vulns":[{"id":"GO-1"}]}]}"#)
        http.on("vulns/GO-1", status: 500, body: "")
        let provider = FileProvider(repos: ["a/one"], files: ["a/one": ["go.mod": "go 1.27\nrequire x.com/y v1.0.0\n"]])

        let repo = await VersionChecker(makeProvider: { _ in provider }, http: http, now: { now }).run(account: account, repo: "a/one").repo

        #expect(repo.vulnerabilities.count == 1)
        #expect(repo.vulnerabilityError != nil)
    }
}

@Suite struct InstallCheckTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    /// lodash 4.17.21 in de root, 4.17.15 direct in packages/api en via express in packages/web.
    static let lock = """
    {"lockfileVersion": 3, "packages": {
      "": {"workspaces": ["packages/*"], "dependencies": {"lodash": "^4.17.21"}},
      "packages/web": {"name": "web", "dependencies": {"express": "^4"}},
      "packages/api": {"name": "api", "dependencies": {"lodash": "4.17.15"}},
      "node_modules/web": {"resolved": "packages/web", "link": true},
      "node_modules/api": {"resolved": "packages/api", "link": true},
      "node_modules/lodash": {"version": "4.17.21"},
      "node_modules/express": {"version": "4.21.0", "dependencies": {"lodash": "4.17.15"}},
      "node_modules/express/node_modules/lodash": {"version": "4.17.15"},
      "packages/api/node_modules/lodash": {"version": "4.17.15"}
    }}
    """

    @Test func queriesEachNameAndVersionOnceAndMapsResultsToEveryInstall() async throws {
        let http = MockHTTPClient()
        // Gesorteerd: express@4.21.0, lodash@4.17.15, lodash@4.17.21.
        http.on("querybatch", body: #"{"results":[{},{"vulns":[{"id":"GHSA-a"}]},{}]}"#)
        http.on("vulns/GHSA-a", body: #"{"id":"GHSA-a","aliases":["CVE-2020-8203"],"database_specific":{"severity":"HIGH"},"affected":[{"package":{"name":"lodash","ecosystem":"npm"},"ranges":[{"events":[{"fixed":"4.17.19"}]}]}]}"#)
        http.on("registry.npmjs.org/lodash/latest", body: #"{"version":"4.17.21"}"#)
        http.on("registry.npmjs.org/express/latest", body: #"{"version":"5.1.0"}"#)
        let provider = FileProvider(repos: ["acme/a", "acme/b"], files: [
            "acme/a": ["package-lock.json": Self.lock],
            "acme/b": ["package-lock.json": Self.lock],
        ])
        let account = Account(kind: .gitHub, organization: "acme", authMethod: .pat, repoWatch: ["acme/a": .prs, "acme/b": .prs])

        let report = await VersionChecker(makeProvider: { _ in provider }, http: http, now: { now }).run(accounts: [account])

        let batches = http.requests.filter { $0.url!.absoluteString.contains("querybatch") }
        #expect(batches.count == 1)
        let body = try JSONSerialization.jsonObject(with: try #require(batches.first?.httpBody)) as? [String: [[String: Any]]]
        #expect(body?["queries"]?.count == 3)
        #expect(http.requests.filter { $0.url!.absoluteString.contains("registry.npmjs.org/lodash/") }.count == 1)
        #expect(http.requests.filter { $0.url!.absoluteString.contains("registry.npmjs.org/express/") }.count == 1)
        #expect(http.requests.filter { $0.url!.absoluteString.contains("vulns/GHSA-a") }.count == 1)

        #expect(report.repos.count == 2)
        for repo in report.repos {
            let hits = repo.vulnerabilities.map { "\($0.workspace) \($0.scope.rawValue) \($0.via.joined(separator: ">"))" }.sorted()
            #expect(hits == ["packages/api direct ", "packages/web transitive express"])
            #expect(repo.vulnerabilities.allSatisfy { $0.id == "GHSA-a" && $0.version == "4.17.15" && $0.fixedIn == "4.17.19" })
            let lodash = try #require(repo.packages.first { $0.name == "lodash" })
            #expect(lodash.installs.count == 3)
            #expect(lodash.version == "4.17.15")
        }

        // Eén melding per lek en package, ook al raakt het twee installs.
        let before = VersionReport(checkedAt: now, repos: report.repos.map {
            RepoVersions(accountId: $0.accountId, repo: $0.repo, components: [])
        })
        let fresh = report.newVulnerabilities(since: before)
        #expect(fresh.count == 2)
        #expect(Set(fresh.map(\.repo)) == ["acme/a", "acme/b"])
    }

    @Test func missingReposGetInstallsToo() async throws {
        let http = MockHTTPClient()
        http.on("querybatch", body: #"{"results":[{},{},{}]}"#)
        http.on("registry.npmjs.org", body: #"{"version":"1.0.0"}"#)
        let provider = FileProvider(repos: ["acme/a", "acme/new"], files: ["acme/new": ["package-lock.json": Self.lock]])
        let account = Account(kind: .gitHub, organization: "acme", authMethod: .pat, repoWatch: ["acme/a": .prs, "acme/new": .prs])
        let known = VersionReport(checkedAt: now, repos: [RepoVersions(accountId: account.id, repo: "acme/a", components: [])])

        let (repos, _) = await VersionChecker(makeProvider: { _ in provider }, http: http, now: { now }).runMissing(accounts: [account], in: known)

        #expect(repos.map(\.repo) == ["acme/new"])
        let lodash = try #require(repos.first?.packages.first { $0.name == "lodash" })
        #expect(Set(lodash.installs.map(\.workspace)) == ["", "packages/api", "packages/web"])
    }
}

@Suite struct RubyGemsCheckTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    @Test func gemfileLockGivesDirectGemsWithTheirLatestVersion() async throws {
        let http = MockHTTPClient()
        http.on("querybatch", body: #"{"results":[{},{},{}]}"#)
        http.on("rubygems.org/api/v1/versions/sinatra/latest.json", body: #"{"version":"4.1.0"}"#)
        http.on("rubygems.org/api/v1/versions/rspec/latest.json", body: #"{"version":"3.13.0"}"#)
        let lock = """
        GEM
          remote: https://rubygems.org/
          specs:
            rack (2.2.9)
            rspec (3.13.0)
            sinatra (3.2.0)
              rack (~> 2.2, >= 2.2.4)

        DEPENDENCIES
          rspec
          sinatra (~> 3.2)
        """
        let gemfile = "source \"https://rubygems.org\"\ngem \"sinatra\"\ngroup :test do\n  gem \"rspec\"\nend\n"
        let provider = FileProvider(repos: ["acme/a"], files: ["acme/a": ["Gemfile": gemfile, "Gemfile.lock": lock]])
        let account = Account(kind: .gitHub, organization: "acme", authMethod: .pat, repoWatch: ["acme/a": .prs])

        let report = await VersionChecker(makeProvider: { _ in provider }, http: http, now: { now }).run(accounts: [account])

        let packages = try #require(report.repos.first?.packages)
        #expect(packages.map(\.name).sorted() == ["rspec", "sinatra"])
        #expect(packages.first { $0.name == "rspec" }?.installs.first?.kind == .dev)
        #expect(report.latestPackages["RubyGems:sinatra"]?.version == "4.1.0")
        #expect(http.requests.filter { $0.url!.absoluteString.contains("versions/rack/") }.isEmpty)
    }
}
