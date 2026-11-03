import AppKit
import PullwatchCore
import Testing

@testable import Pullwatch

/// De SF Symbols die de app bij naam noemt bestaan echt, en de eigen symbolen (de Octicons voor
/// pull requests) staan in de assetcatalogus; een verkeerde naam toont niets.
/// De typen van de app zijn standaard @MainActor (SWIFT_DEFAULT_ACTOR_ISOLATION), dus deze suite ook.
@MainActor @Suite struct SymbolTests {
    /// Of het icoon bestaat: een SF Symbol in het systeem, een eigen symbool in de app.
    private func exists(_ glyph: Glyph) -> Bool {
        switch glyph {
        case .system(let name): NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        case .asset(let name): NSImage(named: name) != nil
        }
    }

    @Test(arguments: ["exclamationmark.triangle", "circle.fill"])
    func menuBarSymbolsExist(_ name: String) {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil)
    }

    @Test func menuBarIconExists() {
        #expect(NSImage(named: "MenuBarIcon") != nil)
    }

    @Test(arguments: [ItemKind.pullRequest, .tag])
    func kindSymbolsExist(_ kind: ItemKind) {
        #expect(exists(kind.glyph))
    }

    @Test(arguments: MainSection.allCases)
    func sectionSymbolsExist(_ section: MainSection) {
        #expect(exists(section.glyph))
    }

    @Test(arguments: PRStatus.allCases)
    func pullRequestIconsAreInTheAssetCatalog(_ status: PRStatus) throws {
        guard case .asset(let name) = status.glyph else {
            Issue.record("\(status) heeft geen eigen icoon")
            return
        }
        let image = try #require(NSImage(named: name))
        // Een symbool, geen plaatje: het schaalt mee met de tekst en volgt de tint.
        #expect(image.isTemplate)
    }

    @Test func pullRequestIconsDiffer() {
        #expect(Set(PRStatus.allCases.map(\.glyph)).count == PRStatus.allCases.count)
    }

    /// Een PR en zijn status: drafts apart, alleen zolang ze open zijn.
    @Test func statusFollowsStateAndDraft() {
        func pr(_ state: PRState, draft: Bool) -> PullRequest {
            PullRequest(
                accountId: UUID(), repo: "r", number: 1, title: "t", authorId: "a", authorName: "a",
                isDraft: draft, createdAt: .now, webURL: URL(string: "https://example.com")!, state: state
            )
        }
        #expect(PRStatus(pr(.open, draft: false)) == .open)
        #expect(PRStatus(pr(.open, draft: true)) == .draft)
        #expect(PRStatus(pr(.merged, draft: true)) == .merged)
        #expect(PRStatus(pr(.closed, draft: false)) == .closed)
        #expect(HistoryEntry.pullRequest(pr(.open, draft: true)).glyph == PRStatus.draft.glyph)
    }

    @Test(arguments: [RepoHealth.problem, .behind, .ok, .unknown])
    func healthSymbolsExist(_ health: RepoHealth) {
        #expect(NSImage(systemSymbolName: health.symbol, accessibilityDescription: nil) != nil)
    }
}
