import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Provider met bestanden per repo en een vast antwoord van het eigen register.
private actor LockfileProvider: PRProvider {
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

/// Wat de lockfile alleen al eigen maakt, blijft binnen, wat het eigen register ook deed (#216):
/// bij een eerste check zonder eerdere gegevens gaat de naam naar geen publiek register en niet
/// naar OSV, en staat het package als niet gecontroleerd.
@Suite struct VersionCheckerInHouseLockfileTests {
    typealias Subject = VersionCheckerInHouseEvidenceTests.Subject
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    /// Hoe het eigen register van het account bij deze check antwoordde.
    enum Read: String, CaseIterable, CustomTestStringConvertible, Sendable {
        /// Het lezen mislukte (netwerk, server).
        case failed
        /// De bron Packageregisters van je accounts staat uit.
        case sourceOff
        /// Het token mag het register niet lezen (een eerste check zonder `gh`).
        case needsPermission
        /// De dienst heeft geen register dat Pullwatch leest.
        case notSupported
        /// Het register is gelezen, maar de repository die het package publiceert wordt niet gevolgd.
        case unfollowedPublisher

        var testDescription: String { rawValue }

        var published: PublishedPackages {
            switch self {
            case .failed: .failed(message: "The network connection was lost.")
            case .sourceOff, .unfollowedPublisher: .packages([])
            case .needsPermission: .needsPermission(reason: "read:packages")
            case .notSupported: .notSupported
            }
        }

        var disabled: Set<DataSourceID> { self == .sourceOff ? [.packageRegistries] : [] }

        var status: InHousePackage.Status {
            switch self {
            case .sourceOff: .sourceOff
            case .needsPermission: .needsPermission(reason: "read:packages")
            case .failed, .notSupported, .unfollowedPublisher: .unconfirmed
            }
        }
    }

    /// Elk eigen package uit de lockfile, bij elk antwoord van het register.
    static let cases: [(Subject, Read)] = VersionCheckerInHouseEvidenceTests.evidenced.flatMap { subject in
        Read.allCases.map { (subject, $0) }
    }

    /// Kent de naam overal: de publieke registers geven een nieuwste versie, OSV een CVE.
    func http(_ subject: Subject) -> MockHTTPClient {
        let http = MockHTTPClient()
        http.on("querybatch", body: #"{"results":[{"vulns":[{"id":"GHSA-leak"}]}]}"#)
        http.on("vulns/GHSA-leak", body: #"""
        {"id":"GHSA-leak","summary":"Public CVE","database_specific":{"severity":"HIGH"},
         "affected":[{"package":{"name":"\#(subject.name)","ecosystem":"\#(subject.ecosystem)"},"ranges":[{"type":"ECOSYSTEM","events":[{"introduced":"0"},{"fixed":"1.4.1"}]}]}]}
        """#)
        http.on("registry.npmjs.org", body: #"{"dist-tags":{"latest":"9.0.0"},"versions":{"9.0.0":{},"1.4.0":{}}}"#)
        return http
    }

    func run(_ subject: Subject, read: Read, files: [String: String]? = nil, http: MockHTTPClient) async -> VersionReport {
        let provider = LockfileProvider(
            files: [subject.repo: files ?? VersionCheckerInHouseEvidenceTests.files(subject, registry: subject.ownRegistry)],
            published: read.published
        )
        return await VersionChecker(
            makeProvider: { _ in provider }, http: http, now: { now }, disabledSources: read.disabled, accounts: [subject.account]
        ).run(accounts: [subject.account])
    }

    /// Geen verzoek, in de URL of de body (OSV), noemt de naam, in welke schrijfwijze ook.
    func expectNoRequest(for name: String, in http: MockHTTPClient) {
        let forms = Set([name, name.replacingOccurrences(of: "/", with: "%2F"), name.replacingOccurrences(of: "/", with: "\\/")].map { $0.lowercased() })
        for request in http.requests {
            let text = ((request.url?.absoluteString ?? "") + String(decoding: request.httpBody ?? Data(), as: UTF8.self)).lowercased()
            for form in forms {
                #expect(!text.contains(form), "verzoek met \(name): \(request.url?.absoluteString ?? "")")
            }
        }
    }

    // MARK: - Bewijs uit de lockfile

    @Test(arguments: cases)
    func `A name the lockfile proves private never reaches a public service`(_ subject: Subject, _ read: Read) async throws {
        let http = http(subject)
        let report = await run(subject, read: read, http: http)

        expectNoRequest(for: subject.name, in: http)
        let inHouse = try #require(report.packageMetadata[subject.key]?.inHouse)
        #expect(inHouse.status == read.status)
        #expect(!inHouse.isPublicName)
        #expect(report.latestPackages[subject.key]?.version == nil)
        let repo = try #require(report.repos.first { $0.repo == subject.repo })
        #expect(repo.vulnerabilities.isEmpty)
    }

    @Test(arguments: Read.allCases)
    func `The package shows as in-house and not checked`(_ read: Read) async throws {
        let subject = VersionCheckerInHouseEvidenceTests.evidenced[0]
        let report = await run(subject, read: read, http: http(subject))

        let row = try #require(report.packageSummaries().first { $0.id == subject.key })
        let inHouse = try #require(row.inHouse)
        #expect(!inHouse.isChecked)
        #expect(inHouse.owner == "acme")
        #expect(inHouse.accountId == subject.account.id)
        #expect(inHouse.type == .npm)
    }

    @Test func `With the source off the repository says the registry source was skipped`() async throws {
        let subject = VersionCheckerInHouseEvidenceTests.evidenced[0]
        let report = await run(subject, read: .sourceOff, http: http(subject))

        let repo = try #require(report.repos.first { $0.repo == subject.repo })
        #expect(repo.skippedSources.contains(.packageRegistries))
    }

    // MARK: - Diensten zonder register dat Pullwatch leest

    /// Gitea en Bitbucket: Pullwatch kent hun register niet, maar een npm-naam met de scope van de
    /// eigenaar uit een niet-publiek register is eigen.
    static let unsupported: [Subject] = [
        Subject(label: "npm on Gitea", account: Account(kind: .gitea, organization: "acme", authMethod: .pat, repoWatch: ["acme/web": .prs], giteaFlavour: .codeberg),
                ecosystem: "npm", type: .npm, name: "@acme/billing",
                ownRegistry: "https://codeberg.org/api/packages/acme/npm/@acme%2Fbilling/-/1.4.0/billing-1.4.0.tgz"),
        Subject(label: "npm on Bitbucket", account: Account(kind: .bitbucket, organization: "acme", authMethod: .pat, repoWatch: ["acme/web": .prs]),
                ecosystem: "npm", type: .npm, name: "@acme/billing",
                ownRegistry: "https://acme.jfrog.io/artifactory/api/npm/npm/@acme/billing/-/billing-1.4.0.tgz"),
    ]

    @Test(arguments: unsupported)
    func `A scoped name of the owner from a private registry stays private on a service without a registry`(_ subject: Subject) async throws {
        let http = http(subject)
        let report = await run(subject, read: .notSupported, http: http)

        expectNoRequest(for: subject.name, in: http)
        #expect(report.packageMetadata[subject.key]?.inHouse?.status == .unconfirmed)
    }

    // MARK: - Waar Pullwatch het niet weet

    @Test func `A scoped name of the owner without a registry in the lockfile is still checked publicly`() async throws {
        // Zonder register in de lockfile kan het een publiek package van de eigenaar op npmjs.com
        // zijn; dat houdt zijn nieuwste versie en zijn CVE's, zoals de documentatie zegt.
        let subject = VersionCheckerInHouseEvidenceTests.evidenced[0].with(name: "@acme/billing", ownRegistry: nil)
        let http = http(subject)
        let report = await run(subject, read: .failed, files: VersionCheckerInHouseEvidenceTests.files(subject, registry: nil), http: http)

        #expect(report.packageMetadata[subject.key]?.inHouse == nil)
        #expect(report.latestPackages[subject.key]?.version == "9.0.0")
    }

    @Test func `A registry of another account is no evidence`() async throws {
        // De lockfile wijst naar GitLab, de repository staat bij GitHub: niet het eigen register.
        let gitLab = VersionCheckerInHouseEvidenceTests.evidenced[0]
        let subject = Subject(
            label: "GitHub", account: VersionCheckerInHouseEvidenceTests.gitHub, ecosystem: "npm", type: .npm, name: gitLab.name,
            ownRegistry: gitLab.ownRegistry
        )
        let report = await run(subject, read: .failed, http: http(subject))

        #expect(report.packageMetadata[subject.key]?.inHouse == nil)
    }

    @Test func `A name an earlier check found in the public registry may be asked again`() async throws {
        let subject = VersionCheckerInHouseEvidenceTests.evidenced[0]
        let http = http(subject)
        let provider = LockfileProvider(
            files: [subject.repo: VersionCheckerInHouseEvidenceTests.files(subject, registry: subject.ownRegistry)], published: Read.failed.published
        )
        let cache = [subject.key: PackageMetadata(latest: "1.3.0", versions: ["1.3.0": VersionMetadata()])]
        let report = await VersionChecker(
            makeProvider: { _ in provider }, http: http, now: { now }, metadataCache: cache, accounts: [subject.account]
        ).run(accounts: [subject.account])

        // De naam staat al in het publieke register: vragen lekt niets.
        #expect(report.packageMetadata[subject.key]?.inHouse == nil)
        #expect(try #require(report.repos.first { $0.repo == subject.repo }).vulnerabilities.map(\.id) == ["GHSA-leak"])
    }
}
