import AppKit
import PullwatchCore
import SwiftUI
import Testing

@testable import Pullwatch

/// Views die in een cel van een `Table` of een rij van een `List` staan, lezen zelf geen model uit
/// de environment: AppKit tekent zo'n cel soms buiten de environment van het venster, en dan stopt
/// SwiftUI de app ("No Observable object of type AccountsModel found"). Zo crashte Pullwatch bij
/// scrollen in de PR-lijst door `ChecksBadge`. Deze tests tekenen die views zonder één model in de
/// environment; leest er weer een een model, dan stopt de testrun hier en niet bij de gebruiker.
@MainActor @Suite struct CellEnvironmentTests {
    private static let pullRequest = PullRequest(
        accountId: UUID(), repo: "octo/app", number: 7, title: "Fix the crash while scrolling",
        authorId: "mona", authorName: "mona", isDraft: false, createdAt: Date(timeIntervalSince1970: 1_790_000_000),
        webURL: URL(string: "https://github.com/octo/app/pull/7")!,
        checks: .counts(CheckCounts(passed: 3, failed: 1, pending: 1))
    )

    private static let item = HistoryItem(entry: .pullRequest(pullRequest), detectedAt: Date(timeIntervalSince1970: 1_790_000_100), isRead: false)

    /// Tekent de view zonder environment en geeft terug of er iets getekend werd.
    private func draws(_ view: some View) -> Bool {
        let renderer = ImageRenderer(content: view.frame(width: 320, height: 24))
        return renderer.nsImage != nil
    }

    @Test(arguments: [true, false])
    func `ChecksBadge draws without a model in the environment`(isEnabled: Bool) {
        #expect(draws(ChecksBadge(checks: Self.pullRequest.checks, isEnabled: isEnabled)))
    }

    @Test(arguments: [true, false])
    func `PullRequestRow draws without a model in the environment`(showsChecks: Bool) {
        #expect(draws(PullRequestRow(item: Self.item, kind: .gitHub, showsChecks: showsChecks)))
    }

    @Test(arguments: [ProviderKind.gitHub, .gitLab, .azureDevOps])
    func `RepoReferenceLabel draws without a model in the environment`(kind: ProviderKind) {
        #expect(draws(RepoReferenceLabel(entry: Self.item.entry, kind: kind)))
    }

    @Test func `AcknowledgementRow draws without a model in the environment`() {
        let component = Acknowledgement(
            id: "sparkle", name: "Sparkle", version: "2.10.1", license: "MIT AND BSD-2-Clause AND Zlib",
            homepage: URL(string: "https://sparkle-project.org")!, file: "sparkle-LICENSE.txt", notice: nil, package: "sparkle"
        )
        #expect(draws(AcknowledgementRow(component: component)))
    }
}
