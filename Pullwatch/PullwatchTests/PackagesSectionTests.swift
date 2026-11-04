import AppKit
import Foundation
import PullwatchCore
import SwiftUI
import Testing

@testable import Pullwatch

/// Het onderdeel Packages: zijn plek in de zijbalk en het menu Ga, de sprongen ernaartoe (vanaf
/// het Overzicht van een repo en vanaf een melding), het hernoemde tabblad van de repo-pagina, de
/// melding van een nieuwe versie, en de cellen die zonder model in de environment tekenen.
@MainActor @Suite struct PackagesSectionTests {
    let router = AppRouter()
    private let accountId = UUID(uuidString: "00000000-0000-0000-0000-0000000000AB")!

    private var package: PublishedPackage {
        PublishedPackage(
            accountId: accountId, name: "ui", type: .npm, owner: "acme", repository: "acme/ui",
            webURL: URL(string: "https://github.com/orgs/acme/packages/npm/package/ui"),
            versions: [
                PublishedVersion(version: "2.4.0", publishedAt: Date(timeIntervalSince1970: 1_790_000_000), tag: "v2.4.0",
                                 runURL: URL(string: "https://gitlab.com/acme/ui/-/pipelines/7")),
                PublishedVersion(version: "2.3.0"),
            ]
        )
    }

    private func draws(_ view: some View) -> Bool {
        ImageRenderer(content: view.frame(width: 320, height: 24)).nsImage != nil
    }

    // MARK: - Plek en sprongen

    @Test func `Packages comes right after Dependencies, with the next shortcut`() throws {
        let index = try #require(MainSection.allCases.firstIndex(of: .packages))
        #expect(MainSection.allCases[index - 1] == .dependencies)
        #expect(MainSection.packages.shortcut == "6")
        #expect(MainSection(rawValue: "packages") == .packages)
    }

    @Test func `The Overview line opens Packages filtered on the repository`() {
        router.showRepo(id: "x")
        let repo = HistoryRepo(accountId: accountId, repo: "acme/ui")

        router.showPublishedPackages(of: repo)

        #expect(router.mainSection == .packages)
        #expect(router.path.isEmpty)
        #expect(router.publishedPackagesRequest == PublishedPackagesRequest(repo: repo))
    }

    @Test func `A notification opens Packages searched on the package`() {
        router.showPublishedPackage("ui")

        #expect(router.mainSection == .packages)
        #expect(router.publishedPackagesRequest == PublishedPackagesRequest(search: "ui"))
    }

    @Test func `The repository tab of dependencies is called Dependencies and keeps its stored value`() {
        #expect(RepoTab(rawValue: "packages") == .dependencies)
        #expect(String(localized: RepoTab.dependencies.title) == String(localized: MainSection.dependencies.title))
        #expect(RepoTab.allCases == [.overview, .check, .dependencies, .security])
    }

    // MARK: - Melding

    @Test func `A new version reads as one passive notification that opens Packages`() throws {
        let path = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let builder = NotificationContentBuilder(bundle: try #require(Bundle(path: path)))

        let content = builder.publishedVersion(package)

        #expect(content.kind == .publishedPackage)
        #expect(content.title == "New version of ui")
        #expect(content.subtitle == "acme/ui")
        #expect(content.body == "Version 2.4.0 published")
        #expect(content.importance.level == .passive)
        #expect(content.payload.section == MainSection.packages.rawValue)
        #expect(content.payload.package == "ui")
        #expect(NotificationGlyph(kind: .publishedPackage) == .publishedPackage)
    }

    @Test func `The notification of a new version is off by default`() {
        #expect(!AppConfig().notifications.publishedPackages)
    }

    // MARK: - Symbolen

    @Test(arguments: PublishedPackageType.known + [PublishedPackageType(rawValue: "something-new")])
    func `Every package type has a symbol that exists`(type: PublishedPackageType) {
        #expect(NSImage(systemSymbolName: type.symbol, accessibilityDescription: nil) != nil)
    }

    @Test func `The section and notification symbols exist`() {
        #expect(NSImage(systemSymbolName: PublishedPackagesView.symbol, accessibilityDescription: nil) != nil)
        if case .system(let name) = NotificationGlyph.publishedPackage.glyph {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil)
        }
    }

    // MARK: - Cellen zonder model

    @Test func `The cells of the Packages table draw without a model in the environment`() {
        #expect(draws(PublishedPackageNameCell(name: "ui", type: .npm)))
        #expect(draws(PublishedPackagePublisherCell(repository: "acme/ui", owner: "acme")))
        #expect(draws(PublishedPackagePublisherCell(repository: nil, owner: "Platform")))
        #expect(draws(PublishedPackageVersionCell(version: "2.4.0", publishedAt: .now, showsDateInHelp: true)))
        #expect(draws(PublishedPackageVersionCell(version: nil, publishedAt: nil)))
        #expect(draws(PublishedPackageDateCell(publishedAt: .now)))
        #expect(draws(PublishedPackageUsersCell(count: 2, isMatchable: true)))
        #expect(draws(PublishedPackageUsersCell(count: 0, isMatchable: false)))
    }

    @Test func `The inspector draws from values only`() {
        let user = PublishedPackageUser(repoId: "\(accountId.uuidString)/acme/web", accountId: accountId, repo: "acme/web", versions: ["2.3.0"], isDirect: true)
        let summary = PublishedPackageSummary(package: package, users: [user])

        let inspector = PublishedPackageInspector(summary: summary, accountName: "@octo", openRepo: { _ in }, showTags: {})

        #expect(ImageRenderer(content: inspector.frame(width: 300, height: 600)).nsImage != nil)
    }

    @Test func `Groups follow the owner, with the packages in table order`() {
        let other = PublishedPackage(accountId: accountId, name: "core", type: .nuGet, owner: "Platform", repository: nil)
        let summaries = [package, other].map { PublishedPackageSummary(package: $0, users: []) }

        let groups = PublishedPackageGroup.groups(summaries)

        #expect(groups.map(\.owner) == ["acme", "Platform"])
        #expect(groups.map { $0.packages.map(\.package.name) } == [["ui"], ["core"]])
    }
}
