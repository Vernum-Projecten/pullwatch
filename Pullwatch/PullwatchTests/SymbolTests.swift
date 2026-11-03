import AppKit
import PullwatchCore
import Testing

@testable import Pullwatch

/// De SF Symbols die de app bij naam noemt bestaan echt; een verkeerde naam toont niets.
@Suite struct SymbolTests {
    @Test(arguments: ["arrow.triangle.pull", "exclamationmark.triangle"])
    func menuBarSymbolsExist(_ name: String) {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil)
    }

    @Test(arguments: [ItemKind.pullRequest, .tag])
    func kindSymbolsExist(_ kind: ItemKind) {
        #expect(NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil) != nil)
    }

    @Test(arguments: MainSection.allCases)
    func sectionSymbolsExist(_ section: MainSection) {
        #expect(NSImage(systemSymbolName: section.symbol, accessibilityDescription: nil) != nil)
    }

    @Test(arguments: [RepoHealth.problem, .behind, .ok, .unknown])
    func healthSymbolsExist(_ health: RepoHealth) {
        #expect(NSImage(systemSymbolName: health.symbol, accessibilityDescription: nil) != nil)
    }
}
