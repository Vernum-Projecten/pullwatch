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

    @Test(arguments: ProviderKind.allCases)
    func providerMarksExist(_ kind: ProviderKind) {
        #expect(exists(kind.glyph))
        #expect(exists(.system(AccountAvatar.placeholderSymbol(for: kind))))
    }

    /// Het GitHub-logo blijft zoals GitHub het geeft: geen template, want dan zou het de tint
    /// volgen (de lichte en donkere variant staan in de assetcatalogus).
    @Test func gitHubMarkKeepsItsColours() throws {
        let logo = try #require(NSImage(named: "GitHubMark"))
        #expect(!logo.isTemplate)
        #expect(ProviderKind.gitHub.glyphKeepsItsColours)
        #expect(!ProviderKind.gitLab.glyphKeepsItsColours)
        #expect(!ProviderKind.azureDevOps.glyphKeepsItsColours)
    }

    @Test(arguments: NotificationGlyph.allCases)
    func notificationGlyphsExist(_ glyph: NotificationGlyph) {
        #expect(exists(glyph.glyph))
    }

    @Test(arguments: NotificationAction.allCases)
    func notificationActionSymbolsExist(_ action: NotificationAction) {
        #expect(NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil) != nil)
    }

    @Test(arguments: ["bell.badge", "bell.slash", "xmark"])
    func notificationSettingsAndMenuSymbolsExist(_ name: String) {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil)
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

    /// De checks hebben de Octicons check, x en dot-fill, als symbool (volgt de tint) en elk een
    /// andere vorm, zodat de stand niet alleen aan de kleur hangt.
    @Test(arguments: CheckState.allCases)
    func `Check icons are symbols in the asset catalog`(_ state: CheckState) throws {
        guard case .asset(let name) = state.glyph else {
            Issue.record("\(state) heeft geen eigen icoon")
            return
        }
        let image = try #require(NSImage(named: name))
        #expect(image.isTemplate)
    }

    @Test func `Check icons differ and amber is in the asset catalog`() {
        #expect(Set(CheckState.allCases.map(\.glyph)).count == CheckState.allCases.count)
        #expect(NSColor(named: "ChecksPending") != nil)
    }

    /// De cel zegt alleen "4/8"; tooltip en VoiceOver zeggen het in woorden, per stand.
    @Test func `Checks are counted and said in words`() {
        let counts = CheckCounts(passed: 3, skipped: 1, failed: 1, pending: 3)
        #expect(counts.fraction == "4/8")
        #expect(!counts.spokenSummary.isEmpty)
        #expect(counts.spokenSummary != CheckCounts(passed: 4, pending: 4).spokenSummary)
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

    /// Waar alleen het icoon staat, zeggen tooltip en VoiceOver soort en status in woorden, per
    /// status verschillend; de betekenis hangt dus niet aan kleur of vorm alleen.
    @Test func everyIconHasItsOwnWords() {
        let names = PRStatus.allCases.map { String(localized: $0.spokenName) } + [String(localized: ItemKind.tag.pillText)]
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { !$0.isEmpty })
    }

    /// Elke update-status heeft een eigen symbool en een eigen kop, zodat de groepen in
    /// Afhankelijkheden niet alleen op kleur verschillen.
    @Test(arguments: UpdateCategory.allCases)
    func updateStatusSymbolsExist(_ category: UpdateCategory) {
        #expect(NSImage(systemSymbolName: category.symbol, accessibilityDescription: nil) != nil)
    }

    /// De ernst in de tabel van kwetsbaarheden: elke ernst een eigen, bestaand symbool.
    @Test func severitySymbolsExistAndDiffer() {
        for level in SeverityLevel.allCases {
            #expect(NSImage(systemSymbolName: level.symbol, accessibilityDescription: nil) != nil, "\(level)")
        }
        #expect(Set(SeverityLevel.allCases.map(\.symbol)).count == SeverityLevel.allCases.count)
    }

    /// De tellers, de kolom In release en de knoppen van de repo-pagina.
    @Test(arguments: ["exclamationmark.shield.fill", "clock.badge.exclamationmark.fill", "shippingbox.fill", "sidebar.trailing",
                      "line.3.horizontal.decrease.circle", "line.3.horizontal.decrease.circle.fill", "ellipsis.circle"])
    func repoPageSymbolsExist(_ name: String) {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil)
    }

    /// De stand van een taal of framework in het raster op de repo-pagina.
    @Test(arguments: [VersionStatus.current, .behind, .eol, .unknown])
    func versionStatusSymbolsExist(_ status: VersionStatus) {
        #expect(NSImage(systemSymbolName: status.symbol, accessibilityDescription: nil) != nil)
    }

    @Test func updateStatusesDiffer() {
        #expect(Set(UpdateCategory.allCases.map(\.symbol)).count == UpdateCategory.allCases.count)
        let titles = UpdateCategory.allCases.map { String(localized: $0.title) }
        #expect(Set(titles).count == titles.count)
    }

    @Test(arguments: [RepoHealth.problem, .behind, .ok, .unknown])
    func healthSymbolsExist(_ health: RepoHealth) {
        #expect(NSImage(systemSymbolName: health.symbol, accessibilityDescription: nil) != nil)
    }
}
