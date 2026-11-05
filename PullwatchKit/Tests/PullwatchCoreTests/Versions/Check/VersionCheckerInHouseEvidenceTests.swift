import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Provider met bestanden per repo en een eigen register.
private actor EvidenceProvider: PRProvider {
    let files: [String: [String: String]]
    let published: PublishedPackages

    init(files: [String: [String: String]], published: PublishedPackages) {
        self.files = files
        self.published = published
    }

    func currentUserId() async throws -> String { "me" }
    func testConnection() async throws -> String { "me" }
    func listRepos() async throws -> [String] { files.keys.sorted() }
    func openPullRequests() async throws -> [PullRequest] { [] }
    func pullRequests(updatedSince since: Date?, limit: Int) async throws -> [PullRequest] { [] }
    func tags(in repos: [String]) async throws -> TagFetch { TagFetch(tags: []) }
    func filePaths(in repo: String, ref: String?) async throws -> [String] { Array((files[repo] ?? [:]).keys).sorted() }
    func fileContent(in repo: String, path: String, ref: String?) async throws -> String {
        guard let content = files[repo]?[path] else { throw ProviderError.server(status: 404) }
        return content
    }
    func invalidateCredentials() async {}
    func publishedPackages(followedRepos: [String]) async throws -> PublishedPackages { published }
}

/// Een dependency is pas eigen met bewijs uit de lockfile, niet op naam (#214): een publiek package
/// met dezelfde naam als een fork in het eigen register houdt zijn publieke versie en zijn CVE's.
@Suite struct VersionCheckerInHouseEvidenceTests {
    static let gitHub = Account(kind: .gitHub, organization: "acme", authMethod: .pat, repoWatch: ["acme/web": .prs, "acme/lib": .prs])
    static let gitLab = Account(kind: .gitLab, organization: "acme", authMethod: .pat, repoWatch: ["acme/web": .prs, "acme/lib": .prs])
    static let azure = Account(kind: .azureDevOps, organization: "acme", authMethod: .pat, repoWatch: ["Shop/web": .prs, "Shop/lib": .prs])
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    /// Eén package in één ecosysteem, bij een account dat een package met dezelfde naam publiceert.
    struct Subject: CustomTestStringConvertible, Sendable {
        let label: String
        let account: Account
        let ecosystem: String
        let type: PublishedPackageType
        let name: String
        /// Het eigen register zoals de lockfile het noemt; nil als de lockfile van dit ecosysteem
        /// geen bron noemt (NuGet) of als het in deze test publiek is.
        let ownRegistry: String?
        var testDescription: String { label }
        var key: String { "\(ecosystem):\(name)" }
        var repo: String { account.kind == .azureDevOps ? "Shop/web" : "acme/web" }
        var owner: String { account.kind == .azureDevOps ? "Shop" : "acme" }

        func with(name: String, ownRegistry: String?) -> Subject {
            Subject(label: label, account: account, ecosystem: ecosystem, type: type, name: name, ownRegistry: ownRegistry)
        }
    }

    /// Een publiek package waarvan het account een fork met dezelfde naam publiceert.
    static let forks: [Subject] = [
        Subject(label: "npm on GitLab", account: gitLab, ecosystem: "npm", type: .npm, name: "left-pad", ownRegistry: nil),
        Subject(label: "RubyGems on GitHub", account: gitHub, ecosystem: "RubyGems", type: .rubyGems, name: "rack", ownRegistry: nil),
        Subject(label: "PyPI on GitLab", account: gitLab, ecosystem: "PyPI", type: .pyPI, name: "requests", ownRegistry: nil),
        Subject(label: "Packagist on GitLab", account: gitLab, ecosystem: "Packagist", type: .composer, name: "monolog/monolog", ownRegistry: nil),
        Subject(label: "NuGet on Azure DevOps", account: azure, ecosystem: "NuGet", type: .nuGet, name: "Newtonsoft.Json", ownRegistry: nil),
        Subject(label: "crates.io on Azure DevOps", account: azure, ecosystem: "crates.io", type: .cargo, name: "serde", ownRegistry: nil),
    ]

    /// Een eigen package met het eigen register in de lockfile.
    static let evidenced: [Subject] = [
        Subject(label: "npm on GitLab", account: gitLab, ecosystem: "npm", type: .npm, name: "acme-billing",
                ownRegistry: "https://gitlab.com/api/v4/projects/42/packages/npm/acme-billing/-/acme-billing-1.4.0.tgz"),
        Subject(label: "npm on Azure DevOps", account: azure, ecosystem: "npm", type: .npm, name: "acme-billing",
                ownRegistry: "https://pkgs.dev.azure.com/acme/_packaging/web/npm/registry/acme-billing/-/acme-billing-1.4.0.tgz"),
        Subject(label: "RubyGems on GitHub", account: gitHub, ecosystem: "RubyGems", type: .rubyGems, name: "acme_billing",
                ownRegistry: "https://rubygems.pkg.github.com/acme/"),
        Subject(label: "PyPI on GitLab", account: gitLab, ecosystem: "PyPI", type: .pyPI, name: "acme-billing",
                ownRegistry: "https://__token__:glpat-s3cr3t@gitlab.com/api/v4/projects/42/packages/pypi/simple"),
        Subject(label: "Packagist on GitLab", account: gitLab, ecosystem: "Packagist", type: .composer, name: "acme/billing",
                ownRegistry: "https://gitlab.com/api/v4/projects/42/packages/composer/archives/acme/billing.zip?sha=0a1b2c"),
    ]

    // MARK: - Bestanden zoals de tools ze schrijven

    /// De bestanden van een repo die `name` op 1.4.0 gebruikt, uit `registry` of anders uit het
    /// publieke register.
    static func files(_ subject: Subject, name: String? = nil, registry: String?) -> [String: String] {
        let name = name ?? subject.name
        switch subject.ecosystem {
        case "npm":
            let resolved = registry ?? "https://registry.npmjs.org/\(name)/-/\(name)-1.4.0.tgz"
            return [
                "package.json": #"{"name":"web","dependencies":{"\#(name)":"^1.4.0"}}"#,
                "package-lock.json": #"""
                {"name":"web","lockfileVersion":3,"requires":true,"packages":{
                  "":{"name":"web","dependencies":{"\#(name)":"^1.4.0"}},
                  "node_modules/\#(name)":{"version":"1.4.0","resolved":"\#(resolved)","integrity":"sha512-abc=="}
                }}
                """#,
            ]
        case "RubyGems":
            return [
                "Gemfile": "source \"https://rubygems.org\"\n\ngem \"\(name)\", \"~> 1.4\"\n",
                "Gemfile.lock": """
                GEM
                  remote: \(registry ?? "https://rubygems.org/")
                  specs:
                    \(name) (1.4.0)

                PLATFORMS
                  ruby

                DEPENDENCIES
                  \(name) (~> 1.4)

                BUNDLED WITH
                   2.5.3
                """,
            ]
        case "PyPI":
            return ["requirements.txt": (registry.map { "--index-url \($0)\n" } ?? "") + "\(name)==1.4.0\n"]
        case "Packagist":
            let dist = registry ?? "https://api.github.com/repos/\(name)/zipball/0a1b2c"
            return [
                "composer.json": #"{"require":{"\#(name)":"^1.4"}}"#,
                "composer.lock": #"""
                {"_readme":["This file locks the dependencies of your project to a known state"],"content-hash":"abc","packages":[
                  {"name":"\#(name)","version":"1.4.0","dist":{"type":"zip","url":"\#(dist)","reference":"0a1b2c"},"type":"library"}
                ],"packages-dev":[]}
                """#,
            ]
        case "NuGet":
            return [
                "src/Web/packages.lock.json": #"""
                {"version":1,"dependencies":{"net8.0":{"\#(name)":{"type":"Direct","requested":"[1.4.0, )","resolved":"1.4.0","contentHash":"ppPF=="}}}}
                """#,
            ]
        default:
            return [
                "Cargo.toml": "[package]\nname = \"app\"\nversion = \"0.1.0\"\n\n[dependencies]\n\(name) = \"1.4\"\n",
                "Cargo.lock": """
                version = 3

                [[package]]
                name = "app"
                version = "0.1.0"
                dependencies = [
                 "\(name)",
                ]

                [[package]]
                name = "\(name)"
                version = "1.4.0"
                source = "\(registry.map { "registry+\($0)" } ?? "registry+https://github.com/rust-lang/crates.io-index")"
                checksum = "0f3a"
                """,
            ]
        }
    }

    /// Wat het account publiceert: het package met dezelfde naam, op 1.5.0.
    static func published(_ subject: Subject, name: String? = nil) -> PublishedPackage {
        PublishedPackage(
            accountId: subject.account.id, name: name ?? subject.name, type: subject.type, owner: subject.owner,
            repository: subject.account.kind == .azureDevOps ? nil : "acme/lib",
            versions: [PublishedVersion(version: "1.5.0"), PublishedVersion(version: "1.4.0")]
        )
    }

    /// OSV kent een kwetsbaarheid in de publieke `name` 1.4.0; de registers kennen niets.
    func http(_ subject: Subject, name: String? = nil) -> MockHTTPClient {
        let http = MockHTTPClient()
        let name = name ?? subject.name
        http.on("querybatch", body: #"{"results":[{"vulns":[{"id":"GHSA-fork"}]}]}"#)
        http.on("vulns/GHSA-fork", body: #"""
        {"id":"GHSA-fork","summary":"Public CVE","database_specific":{"severity":"HIGH"},
         "affected":[{"package":{"name":"\#(name)","ecosystem":"\#(subject.ecosystem)"},"ranges":[{"type":"ECOSYSTEM","events":[{"introduced":"0"},{"fixed":"1.4.1"}]}]}]}
        """#)
        return http
    }

    func run(
        _ subject: Subject, files: [String: [String: String]], published: PublishedPackages, http: MockHTTPClient,
        cache: [String: PackageMetadata] = [:]
    ) async -> VersionReport {
        let provider = EvidenceProvider(files: files, published: published)
        return await VersionChecker(
            makeProvider: { _ in provider }, http: http, now: { now }, metadataCache: cache, accounts: [subject.account]
        ).run(accounts: [subject.account])
    }

    /// Geen verzoek, ook niet in de body (OSV), noemt de eigen naam.
    func expectNoRequest(for name: String, in http: MockHTTPClient) {
        for request in http.requests {
            let text = (request.url?.absoluteString ?? "") + String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            for form in [name, name.replacingOccurrences(of: "/", with: "%2F"), name.replacingOccurrences(of: "/", with: "\\/")] {
                #expect(!text.contains(form), "verzoek met \(name): \(request.url?.absoluteString ?? "")")
            }
        }
    }

    func repo(_ report: VersionReport, _ subject: Subject) throws -> RepoVersions {
        try #require(report.repos.first { $0.repo == subject.repo })
    }

    // MARK: - Zelfde naam, publiek package

    @Test(arguments: forks)
    func `A public package with a same-named private fork keeps its public CVEs`(_ subject: Subject) async throws {
        let http = http(subject)
        let report = await run(
            subject, files: [subject.repo: Self.files(subject, registry: nil)], published: .packages([Self.published(subject)]), http: http
        )

        #expect(report.packageMetadata[subject.key]?.inHouse == nil)
        #expect(report.latestPackages[subject.key]?.version != "1.5.0")
        #expect(try repo(report, subject).vulnerabilities.map(\.id) == ["GHSA-fork"])
    }

    @Test func `The public package says the account also publishes the name`() async throws {
        let subject = Self.forks[0]
        let http = http(subject)
        http.on("registry.npmjs.org/left-pad", body: #"{"dist-tags":{"latest":"1.3.0"},"versions":{"1.3.0":{},"1.4.0":{}}}"#)
        let report = await run(
            subject, files: [subject.repo: Self.files(subject, registry: nil)], published: .packages([Self.published(subject)]), http: http
        )

        let namesake = try #require(report.packageMetadata[subject.key]?.alsoPublishedBy)
        #expect(namesake.source == "acme/lib")
        #expect(report.packageMetadata[subject.key]?.inHouse == nil)
        let row = try #require(report.packageSummaries().first { $0.id == subject.key })
        #expect(row.alsoPublishedBy?.source == "acme/lib")
        #expect(row.inHouse == nil)
    }

    @Test func `One install without evidence keeps the name public for every repository`() async throws {
        let subject = Self.evidenced[0]
        let http = http(subject)
        let files = [
            "acme/web": Self.files(subject, registry: subject.ownRegistry),
            "acme/lib": Self.files(subject, registry: nil),
        ]
        let report = await run(subject, files: files, published: .packages([Self.published(subject)]), http: http)

        #expect(report.packageMetadata[subject.key]?.inHouse == nil)
        #expect(report.repos.allSatisfy { $0.vulnerabilities.map(\.id) == ["GHSA-fork"] })
    }

    // MARK: - Met bewijs

    @Test(arguments: evidenced)
    func `An install from the account's own registry stays in-house`(_ subject: Subject) async throws {
        let http = http(subject)
        let report = await run(
            subject, files: [subject.repo: Self.files(subject, registry: subject.ownRegistry)], published: .packages([Self.published(subject)]),
            http: http
        )

        let inHouse = try #require(report.packageMetadata[subject.key]?.inHouse)
        #expect(inHouse.status == .checked)
        #expect(!inHouse.isPublicName)
        #expect(report.latestPackages[subject.key]?.version == "1.5.0")
        let install = try #require(try repo(report, subject).packages.first { $0.key == subject.key }?.installs.first)
        #expect(install.registry != nil)
        #expect(install.registry?.contains("glpat") == false)
    }

    @Test(arguments: evidenced)
    func `A private-only name never reaches a public registry or OSV`(_ subject: Subject) async throws {
        let http = http(subject)
        let report = await run(
            subject, files: [subject.repo: Self.files(subject, registry: subject.ownRegistry)], published: .packages([Self.published(subject)]),
            http: http
        )

        #expect(report.packageMetadata[subject.key]?.inHouse != nil)
        #expect(try repo(report, subject).vulnerabilities.isEmpty)
        expectNoRequest(for: subject.name, in: http)
    }

    @Test func `A scoped npm name of the owner needs no registry in the lockfile`() async throws {
        let subject = Self.evidenced[0].with(name: "@acme/billing", ownRegistry: nil)
        let http = http(subject)
        let report = await run(
            subject, files: [subject.repo: Self.files(subject, registry: nil)], published: .packages([Self.published(subject)]), http: http
        )

        #expect(report.packageMetadata[subject.key]?.inHouse?.status == .checked)
        #expect(report.latestPackages[subject.key]?.version == "1.5.0")
        expectNoRequest(for: subject.name, in: http)
    }

    @Test func `An in-house fork of a name the public registry knows is still checked by OSV`() async throws {
        let fork = Self.forks[0]
        let subject = fork.with(name: fork.name, ownRegistry: "https://gitlab.com/api/v4/projects/42/packages/npm/left-pad/-/left-pad-1.4.0.tgz")
        let http = http(subject)
        // Een eerdere check vond left-pad op npmjs.com.
        let cache = [subject.key: PackageMetadata(latest: "1.3.0", versions: ["1.3.0": VersionMetadata()])]
        let report = await run(
            subject, files: [subject.repo: Self.files(subject, registry: subject.ownRegistry)], published: .packages([Self.published(subject)]),
            http: http, cache: cache
        )

        let inHouse = try #require(report.packageMetadata[subject.key]?.inHouse)
        #expect(inHouse.isPublicName)
        #expect(report.latestPackages[subject.key]?.version == "1.5.0")
        #expect(try repo(report, subject).vulnerabilities.map(\.id) == ["GHSA-fork"])
        // De nieuwste versie komt uit het eigen register, niet van npmjs.com.
        #expect(!http.requests.contains { $0.url?.host() == "registry.npmjs.org" })
    }

    // MARK: - Verouderde gegevens

    enum Stale: String, CaseIterable, Sendable {
        case accountRemoved, accountPaused, packageUnlisted
    }

    @Test(arguments: Stale.allCases)
    func `An in-house package of a gone publisher is public again`(_ stale: Stale) async throws {
        let subject = Self.evidenced[0]
        var publisher = subject.account
        publisher.isPaused = stale == .accountPaused
        let user = Account(kind: .gitHub, organization: "acme", authMethod: .pat, repoWatch: ["acme/web": .prs])
        let cached = try #require(VersionChecker.metadata(of: Self.published(subject), repositoryURL: nil))
        let previous = AccountPackages(
            accountId: publisher.id, result: .packages(stale == .packageUnlisted ? [] : [Self.published(subject)]), checkedAt: now
        )
        let provider = EvidenceProvider(files: ["acme/web": Self.files(subject, registry: subject.ownRegistry)], published: .notSupported)
        let http = http(subject)

        let checked = await VersionChecker(
            makeProvider: { _ in provider }, http: http, now: { now }, metadataCache: [subject.key: cached],
            publishedPackages: [previous], accounts: stale == .accountRemoved ? [user] : [user, publisher]
        ).run(account: user, repo: "acme/web")

        #expect(checked.metadata[subject.key]?.inHouse == nil)
        #expect(checked.latest[subject.key]?.version != "1.5.0")
        #expect(checked.repo.vulnerabilities.map(\.id) == ["GHSA-fork"])
    }

    @Test func `An active publisher keeps the in-house package of the last check`() async throws {
        let subject = Self.evidenced[0]
        let user = Account(kind: .gitHub, organization: "acme", authMethod: .pat, repoWatch: ["acme/web": .prs])
        let previous = AccountPackages(accountId: subject.account.id, result: .packages([Self.published(subject)]), checkedAt: now)
        let provider = EvidenceProvider(files: ["acme/web": Self.files(subject, registry: subject.ownRegistry)], published: .notSupported)
        let http = http(subject)

        let checked = await VersionChecker(
            makeProvider: { _ in provider }, http: http, now: { now }, publishedPackages: [previous], accounts: [user, subject.account]
        ).run(account: user, repo: "acme/web")

        #expect(checked.metadata[subject.key]?.inHouse?.status == .checked)
        expectNoRequest(for: subject.name, in: http)
    }
}
