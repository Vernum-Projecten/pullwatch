import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Provider zonder bestanden die bijhoudt naar welke eigen packages gevraagd is.
private actor PackagesProvider: PRProvider {
    let repos: [String]
    let result: Result<PublishedPackages, ProviderError>
    private(set) var asked: [[String]] = []

    init(repos: [String], result: Result<PublishedPackages, ProviderError>) {
        self.repos = repos
        self.result = result
    }

    func currentUserId() async throws -> String { "me" }
    func testConnection() async throws -> String { "me" }
    func listRepos() async throws -> [String] { repos }
    func openPullRequests() async throws -> [PullRequest] { [] }
    func pullRequests(updatedSince since: Date?, limit: Int) async throws -> [PullRequest] { [] }
    func tags(in repos: [String]) async throws -> TagFetch { TagFetch(tags: []) }
    func filePaths(in repo: String, ref: String?) async throws -> [String] { [] }
    func fileContent(in repo: String, path: String, ref: String?) async throws -> String { "" }
    func invalidateCredentials() async {}

    func publishedPackages(followedRepos: [String]) async throws -> PublishedPackages {
        asked.append(followedRepos)
        return try result.get()
    }
}

/// De dagelijkse versiecheck haalt per account de eigen packages op, alleen met de bron aan.
@Suite struct VersionCheckerPackagesTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    func account() -> Account {
        Account(kind: .gitHub, organization: "acme", authMethod: .pat, repoWatch: ["acme/web": .prs, "acme/old": .none])
    }

    var found: PublishedPackages {
        .packages([PublishedPackage(accountId: fixedAccountId, name: "web", type: .npm, owner: "acme", repository: "acme/web")])
    }

    @Test func `The check asks each account once with its followed repositories`() async {
        let provider = PackagesProvider(repos: ["acme/web", "acme/old"], result: .success(found))
        let account = account()

        let report = await VersionChecker(makeProvider: { _ in provider }, http: MockHTTPClient(), now: { now }).run(accounts: [account])

        #expect(await provider.asked == [["acme/web"]])
        #expect(report.publishedPackages == [AccountPackages(accountId: account.id, result: found, checkedAt: now)])
    }

    @Test func `With the source off nothing is asked`() async {
        let provider = PackagesProvider(repos: ["acme/web"], result: .success(found))

        let report = await VersionChecker(
            makeProvider: { _ in provider }, http: MockHTTPClient(), now: { now }, disabledSources: [.packageRegistries]
        ).run(accounts: [account()])

        #expect(await provider.asked.isEmpty)
        #expect(report.publishedPackages.isEmpty)
    }

    @Test func `A failing registry is stored as failed and the check goes on`() async {
        let provider = PackagesProvider(repos: ["acme/web"], result: .failure(.network("offline")))

        let report = await VersionChecker(makeProvider: { _ in provider }, http: MockHTTPClient(), now: { now }).run(accounts: [account()])

        #expect(report.publishedPackages.map(\.result) == [.failed(message: ProviderError.network("offline").userMessage)])
        #expect(report.repos.map(\.repo) == ["acme/web"])
    }

    @Test func `A service without a registry is not supported`() async {
        let provider = FileProvider(repos: ["acme/web"], files: [:])

        let report = await VersionChecker(makeProvider: { _ in provider }, http: MockHTTPClient(), now: { now }).run(accounts: [account()])

        #expect(report.publishedPackages.map(\.result) == [.notSupported])
    }

    @Test func `Checking one repository again does not ask for packages`() async {
        let provider = PackagesProvider(repos: ["acme/web"], result: .success(found))

        _ = await VersionChecker(makeProvider: { _ in provider }, http: MockHTTPClient(), now: { now }).run(account: account(), repo: "acme/web")

        #expect(await provider.asked.isEmpty)
    }
}
