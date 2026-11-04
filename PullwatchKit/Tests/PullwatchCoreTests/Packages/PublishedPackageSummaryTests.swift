import Foundation
import Testing
@testable import PullwatchCore

/// De rijen van de Packages-sectie (wie een eigen package gebruikt, uit de check op eigen
/// packages), de nieuwe versies tussen twee checks voor de melding, en de schakelaar van die melding.
@Suite struct PublishedPackageSummaryTests {
    static let account = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    static let checkedAt = Date(timeIntervalSince1970: 1_790_000_000)

    static func ui(_ latest: String) -> PublishedPackage {
        PublishedPackage(
            accountId: account, name: "ui", type: .npm, owner: "acme", repository: "acme/ui",
            versions: [PublishedVersion(version: latest), PublishedVersion(version: "2.0.0")]
        )
    }

    static let image = PublishedPackage(
        accountId: account, name: "acme/web", type: .container, owner: "acme", repository: "acme/web",
        versions: [PublishedVersion(version: "1.0.0")]
    )

    /// Azure Artifacts: geen repository, de eigenaar is het project.
    static let feedPackage = PublishedPackage(accountId: account, name: "Acme.Core", type: .nuGet, owner: "Platform", repository: nil, latestVersion: "3.1.0")

    static func use(_ name: String, _ versions: [String], scope: DependencyScope = .direct) -> PackageUse {
        PackageUse(ecosystem: "npm", name: name, installs: versions.map {
            PackageInstall(version: $0, workspace: "", scope: scope, source: "package-lock.json")
        })
    }

    static func report(_ packages: [PublishedPackage], repos: [RepoVersions] = []) -> VersionReport {
        let ui = packages.first { $0.name == "ui" }
        let inHouse = ui.map { VersionChecker.metadata(of: $0, repositoryURL: nil) }
        return VersionReport(
            checkedAt: checkedAt, repos: repos,
            packageMetadata: inHouse.map { ["npm:@acme/ui": $0] } ?? [:],
            publishedPackages: [AccountPackages(accountId: account, result: .packages(packages), checkedAt: checkedAt)]
        )
    }

    static let repos = [
        RepoVersions(accountId: account, repo: "acme/web", components: [], packages: [use("@acme/ui", ["2.3.0", "2.1.0", "2.3.0"])]),
        RepoVersions(accountId: account, repo: "acme/admin", components: [], otherPackages: [use("@acme/ui", ["2.0.0"], scope: .transitive)]),
        RepoVersions(accountId: account, repo: "acme/api", components: [], packages: [use("left-pad", ["1.3.0"])]),
    ]

    @Test func `Used by lists the repositories with their versions, oldest first`() throws {
        let summaries = Self.report([Self.ui("2.3.0"), Self.image], repos: Self.repos).publishedPackageSummaries()

        let ui = try #require(summaries.first { $0.package.name == "ui" })
        #expect(ui.users.map(\.repo) == ["acme/admin", "acme/web"])
        #expect(ui.users.map(\.versions) == [["2.0.0"], ["2.1.0", "2.3.0"]])
        #expect(ui.users.map(\.isDirect) == [false, true])
        #expect(ui.isMatchable)
    }

    @Test func `A container image is not matched, so its usage is unknown`() throws {
        let summaries = Self.report([Self.ui("2.3.0"), Self.image], repos: Self.repos).publishedPackageSummaries()

        let image = try #require(summaries.first { $0.package.type == .container })
        #expect(image.users.isEmpty)
        #expect(!image.isMatchable)
    }

    @Test func `A package without repository stays, under its project`() throws {
        let summaries = Self.report([Self.feedPackage]).publishedPackageSummaries()

        let package = try #require(summaries.first)
        #expect(package.package.repository == nil)
        #expect(package.package.owner == "Platform")
        #expect(package.package.latestVersion == "3.1.0")
    }

    @Test func `A new latest version between two checks gives one notification`() {
        let before = Self.report([Self.ui("2.3.0"), Self.image])
        let after = Self.report([Self.ui("2.4.0"), Self.image])

        #expect(after.newPublishedVersions(since: before).map(\.latestVersion) == ["2.4.0"])
    }

    @Test func `The same version, a first check or a new package give no notification`() {
        let before = Self.report([Self.ui("2.3.0")])

        #expect(before.newPublishedVersions(since: before).isEmpty)
        #expect(before.newPublishedVersions(since: nil).isEmpty)
        #expect(Self.report([Self.ui("2.3.0"), Self.feedPackage]).newPublishedVersions(since: before).isEmpty)
    }

    @Test func `The notification of a new version is off by default, also in an older config`() throws {
        #expect(!NotificationSettings().publishedPackages)
        #expect(!NotificationSettings()[.publishedPackage])
        #expect(NotificationKind.switchable.contains(.publishedPackage))
        let old = try JSONDecoder().decode(NotificationSettings.self, from: Data(#"{"packageUpdates":true}"#.utf8))
        #expect(!old.publishedPackages)
    }
}
