import Foundation
import PullwatchCore
import Testing

@testable import Pullwatch

/// Een sprong naar PR's of Tags met filters (een auteur, een repo) via `AppRouter`. Elke sprong is
/// een nieuwe stack in het hoofdvenster, zodat de lijst die weggaat niets meer verandert terwijl
/// hij verdwijnt; anders waarschuwt AppKit voor een reentrante tabel-delegate (#204).
@MainActor @Suite struct HistoryRoutingTests {
    let router = AppRouter()
    let repo = HistoryRepo(accountId: UUID(), repo: "octocat/hello-world")

    @Test func `A jump with a repository opens the pull requests with that token`() {
        router.showHistory(.pullRequest, repo: repo)

        #expect(router.mainSection == .pullRequests)
        #expect(router.historyTokens == [.repo(repo)])
    }

    @Test func `A jump with an author and a repository keeps both tokens`() {
        router.showHistory(.tag, author: "mona", repo: repo)

        #expect(router.mainSection == .tags)
        #expect(router.historyTokens == [.author("mona"), .repo(repo)])
    }

    @Test func `Every jump is a new stack, also to the section already shown`() {
        router.navigate(to: .pullRequests)
        let first = router.navigation
        router.navigate(to: .pullRequests)

        #expect(router.navigation != first)
    }

    @Test func `A jump elsewhere starts without the tokens of the last one`() {
        router.showHistory(.pullRequest, repo: repo)
        let jump = router.navigation
        router.navigate(to: .repos)

        #expect(router.historyTokens.isEmpty)
        #expect(router.navigation != jump)
    }

    @Test func `Choosing another item in the sidebar drops the tokens`() {
        router.showHistory(.pullRequest, author: "mona")
        router.sidebarSelection = .section(.tags)

        #expect(router.historyTokens.isEmpty)
        #expect(router.path.isEmpty)
    }
}
