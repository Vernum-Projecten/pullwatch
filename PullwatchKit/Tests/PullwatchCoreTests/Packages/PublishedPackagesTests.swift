import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Het model van de eigen packages: opslaan en teruglezen, ook van oudere of nieuwere gegevens, en
/// hoe het rapport ze bewaart.
@Suite struct PublishedPackagesTests {
    let date = Date(timeIntervalSince1970: 1_792_000_000)
    let accountId = fixedAccountId

    func package(_ name: String = "web", versions: [PublishedVersion] = []) -> PublishedPackage {
        PublishedPackage(
            accountId: accountId, name: name, type: .npm, owner: "acme", repository: "acme/web", visibility: .private,
            webURL: URL(string: "https://github.com/orgs/acme/packages/npm/package/\(name)"), versions: versions
        )
    }

    func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    // MARK: - Model

    @Test func `The latest version and its date come from the newest version`() {
        let found = package(versions: [
            PublishedVersion(version: "2.3.0", publishedAt: date), PublishedVersion(version: "2.2.0", publishedAt: date - 86400),
        ])
        #expect(found.latestVersion == "2.3.0")
        #expect(found.publishedAt == date)
        #expect(found.id == "acme/npm/web")
    }

    @Test func `Only the recent versions are kept`() {
        let found = package(versions: (0..<25).map { PublishedVersion(version: "1.\($0).0") })
        #expect(found.versions.count == PublishedPackage.recentVersionLimit)
        #expect(found.versions.first?.version == "1.0.0")
    }

    // MARK: - Recente versies (#229)

    @Test func `The stable release stays behind many newer pre-releases`() {
        let betas = (1...12).reversed().map { PublishedVersion(version: "3.0.0-beta.\($0)") }
        let found = package(versions: betas + [PublishedVersion(version: "2.9.0"), PublishedVersion(version: "2.8.0")])

        #expect(found.versions.count == PublishedPackage.recentVersionLimit)
        #expect(found.versions.first?.version == "3.0.0-beta.12")
        #expect(found.versions.last?.version == "2.9.0", "de hoogste stabiele, niet de nieuwste stabiele die er niet bij past")
        #expect(found.latestVersion == "3.0.0-beta.12")
        #expect(found.releasedVersion == "2.9.0")
        #expect(found.newestPrerelease == "3.0.0-beta.12")
    }

    @Test func `A stable release among the recent versions changes nothing`() {
        let items = ["2.0.0-rc.1", "1.9.0"] + (0..<12).map { "1.\(8 - $0 / 2).\($0 % 2)" }
        #expect(PublishedPackage.recentVersions(items) { $0 } == Array(items.prefix(PublishedPackage.recentVersionLimit)))
    }

    @Test func `Without a stable release only the first versions are kept`() {
        let items = (1...12).reversed().map { "3.0.0-beta.\($0)" } + ["main"]
        #expect(PublishedPackage.recentVersions(items) { $0 } == Array(items.prefix(PublishedPackage.recentVersionLimit)))
    }

    @Test func `The highest stable release wins, not the newest`() {
        let items = (1...10).reversed().map { "3.0.0-beta.\($0)" } + ["2.8.1", "2.9.0"]
        #expect(PublishedPackage.recentVersions(items) { $0 }.last == "2.9.0")
    }

    @Test(arguments: [
        PublishedPackages.packages([]), .needsPermission(reason: "read:packages ontbreekt"), .notSupported,
        .failed(message: "Geen netwerk"),
    ])
    func `Every result survives a round trip`(result: PublishedPackages) throws {
        #expect(try roundTrip(result) == result)
    }

    @Test func `Packages with versions survive a round trip`() throws {
        let result = PublishedPackages.packages([package(versions: [
            PublishedVersion(version: "2.3.0", publishedAt: date, webURL: URL(string: "https://x/1"), tag: "v2.3.0",
                             runURL: URL(string: "https://x/run/1")),
        ])])
        #expect(try roundTrip(result) == result)
    }

    @Test(arguments: [
        ("npm", PublishedPackageType.npm, "npm"), ("NuGet", .nuGet, "NuGet"), ("maven", .maven, "Maven"),
        ("rubygems", .rubyGems, "RubyGems"), ("container", .container, nil), ("conan", PublishedPackageType(rawValue: "conan"), nil),
    ])
    func `A type keeps its name and knows its ecosystem`(raw: String, type: PublishedPackageType, ecosystem: String?) throws {
        let decoded = try JSONDecoder().decode(PublishedPackageType.self, from: Data(#""\#(raw)""#.utf8))
        #expect(decoded == type)
        #expect(decoded.dependencyEcosystem == ecosystem)
    }

    // MARK: - Tolerant lezen

    @Test func `A package from a newer version with unknown fields still reads`() throws {
        let json = #"""
        {"accountId":"00000000-0000-0000-0000-000000000001","name":"web","type":"helm","owner":"acme",
         "visibility":"limited","downloads":12,"versions":[{"version":"1.0.0"},{"nope":true}]}
        """#
        let found = try JSONDecoder().decode(PublishedPackage.self, from: Data(json.utf8))
        #expect(found.type == .helm)
        #expect(found.visibility == nil, "een zichtbaarheid die Pullwatch niet kent")
        #expect(found.repository == nil)
        #expect(found.versions.map(\.version) == ["1.0.0"], "een kapotte versie valt weg")
    }

    @Test func `A package stored before container versions reads as a real version`() throws {
        let json = #"""
        {"accountId":"00000000-0000-0000-0000-000000000001","name":"ferrobridge","type":"container","owner":"acme",
         "latestVersion":"sha256-7e0fd343419965e2b3c3151dbd7a601ac1e97f42caadbf2ef9d50f86883d1957",
         "versions":[{"version":"sha256-7e0fd343419965e2b3c3151dbd7a601ac1e97f42caadbf2ef9d50f86883d1957"}]}
        """#
        let found = try JSONDecoder().decode(PublishedPackage.self, from: Data(json.utf8))
        #expect(found.latestKind == .version)
        #expect(found.latestTag == .absent)
        #expect(found.versions.map(\.isLatestTag) == [false])
    }

    @Test func `An unknown kind of latest version from a newer Pullwatch reads as a version`() throws {
        let json = #"""
        {"accountId":"00000000-0000-0000-0000-000000000001","name":"web","type":"container","owner":"acme",
         "latestVersion":"1.0.0","latestKind":"digest","latestTag":{"pointsSomewhere":{}}}
        """#
        let found = try JSONDecoder().decode(PublishedPackage.self, from: Data(json.utf8))
        #expect(found.latestKind == .version)
        #expect(found.latestTag == .absent)
    }

    @Test(arguments: [
        PublishedPackage.LatestTag.absent, .onLatestVersion, .otherVersion("0.9.0"), .unversionedBuild,
    ])
    func `A container package survives a round trip`(latestTag: PublishedPackage.LatestTag) throws {
        let found = PublishedPackage(
            accountId: accountId, name: "web", type: .container, owner: "acme", repository: "acme/web", latestVersion: "main",
            versions: [PublishedVersion(version: "1.0.0", isLatestTag: true)], latestKind: .floatingTag, latestTag: latestTag
        )
        #expect(try roundTrip(found) == found)
    }

    @Test func `An unknown result reads as not supported`() throws {
        let json = #"{"status":"somethingNew","detail":"x"}"#
        #expect(try JSONDecoder().decode(PublishedPackages.self, from: Data(json.utf8)) == .notSupported)
    }

    @Test func `A stored report from before published packages still reads`() throws {
        let json = #"{"checkedAt": 0, "repos": [], "format": 2}"#
        let report = try JSONDecoder().decode(VersionReport.self, from: Data(json.utf8))
        #expect(report.publishedPackages.isEmpty)
        #expect(!report.isOutdatedFormat, "eigen packages maken een rapport niet ouderwets")
    }

    @Test func `Broken published packages do not make the report unreadable`() throws {
        let json = #"""
        {"checkedAt": 0, "repos": [], "format": 2, "publishedPackages": [
          {"accountId":"00000000-0000-0000-0000-000000000001","checkedAt":0,"result":{"status":"notSupported"}},
          {"accountId":"kapot"}
        ]}
        """#
        let report = try JSONDecoder().decode(VersionReport.self, from: Data(json.utf8))
        #expect(report.publishedPackages.map(\.result) == [.notSupported])
    }

    // MARK: - In het rapport

    @Test func `The report keeps published packages through refreshing a repository and advisories`() throws {
        let packages = [AccountPackages(accountId: accountId, result: .packages([package()]), checkedAt: date)]
        let report = VersionReport(checkedAt: date, repos: [], publishedPackages: packages)
        let repo = RepoVersions(accountId: accountId, repo: "acme/web", components: [])

        #expect(report.replacing(repo).publishedPackages == packages)
        #expect(report.carryingAdvisories(from: report).publishedPackages == packages)
        #expect(report.carryingSeenDates(from: report).publishedPackages == packages)
        #expect(try roundTrip(report).publishedPackages == packages)
        #expect(report.allPublishedPackages.map(\.name) == ["web"])
    }

    @Test func `With the source off the shown report has no published packages`() {
        let packages = [AccountPackages(accountId: accountId, result: .packages([package()]), checkedAt: date)]
        let report = VersionReport(checkedAt: date, repos: [], publishedPackages: packages)

        #expect(report.visible(disabled: [.packageRegistries], accountKinds: [:]).publishedPackages.isEmpty)
        #expect(report.visible(disabled: [.npm], accountKinds: [:]).publishedPackages == packages)
    }

    @Test func `A failed registry keeps the packages of the previous check`() {
        let other = UUID()
        let previous = VersionReport(checkedAt: date, repos: [], publishedPackages: [
            AccountPackages(accountId: accountId, result: .packages([package("old")]), checkedAt: date),
            AccountPackages(accountId: other, result: .packages([package("gone")]), checkedAt: date),
        ])
        let fresh = VersionReport(checkedAt: date + 86400, repos: [], publishedPackages: [
            AccountPackages(accountId: accountId, result: .failed(message: "Geen netwerk"), checkedAt: date + 86400),
            AccountPackages(accountId: other, result: .needsPermission(reason: "read:packages"), checkedAt: date + 86400),
        ])

        let carried = fresh.carryingPublishedPackages(from: previous).publishedPackages

        #expect(carried.map(\.result) == [.packages([package("old")]), .needsPermission(reason: "read:packages")])
        #expect(carried.first?.checkedAt == date, "van de vorige check, met zijn eigen datum")
    }

    @Test func `The source of package registries is in the catalogue under versions`() {
        let source = DataSource.source(.packageRegistries)
        #expect(source.group == .versions)
        #expect(source.endpoints.map(\.absoluteString) == ["https://api.github.com"])
        let off = SourcesOverview.text(
            config: AppConfig(disabledSources: [.packageRegistries]), appVersion: "1.0", date: date, locale: Locale(identifier: "nl_NL")
        )
        #expect(off.contains("- Packageregisters van je accounts: uit."))
    }
}
