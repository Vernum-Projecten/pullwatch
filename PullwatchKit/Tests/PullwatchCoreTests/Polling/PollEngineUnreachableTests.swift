import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Gevolgde repo's die het token niet kan lezen (`PollEngine.unreachableRepos()`): uit de tag- en
/// de branch-poll, elk op zijn eigen ritme, en weer weg zodra de toegang terug is.
@Suite struct PollEngineUnreachableTests {
    private let clock = TestClock()
    private let provider = MockProvider()
    private let engine: PollEngine
    private let account = Account.fixture(repoWatch: ["Proj/A": .both, "proj/b": .both])

    init() {
        let clock = clock
        let provider = provider
        engine = PollEngine(makeProvider: { _ in provider }, store: nil, now: { clock.now })
    }

    /// Eén ronde zoals de app hem doet: eerst `poll`, dan `pollBranches`.
    private func round(_ accounts: [Account]? = nil) async {
        let accounts = accounts ?? [account]
        _ = await engine.poll(accounts: accounts, interval: 120, retention: .oneYear)
        _ = await engine.pollBranches(accounts: accounts)
    }

    /// Naar de volgende tag- en branch-poll.
    private func nextRound() async {
        clock.advance(max(PollEngine.tagInterval, PollEngine.branchInterval))
        await round()
    }

    @Test func `A repository the tag poll cannot read is reported in its own spelling`() async {
        await provider.set(unavailableTagRepos: ["proj/a"])

        await round()

        #expect(await engine.unreachableRepos()[account.id]?.repos == ["Proj/A"])
    }

    @Test func `A repository the branch poll cannot read is reported`() async {
        await provider.set(branchFetch: BranchFetch(heads: [], unavailableRepos: ["proj/b"]))

        await round()

        #expect(await engine.unreachableRepos()[account.id]?.repos == ["proj/b"])
    }

    @Test func `Tags and branches together give each repository once`() async throws {
        await provider.set(unavailableTagRepos: ["proj/a", "proj/b"])
        await provider.set(branchFetch: BranchFetch(heads: [], unavailableRepos: ["proj/b"]))

        await round()

        let unreachable = try #require(await engine.unreachableRepos()[account.id])
        #expect(unreachable.repos == ["Proj/A", "proj/b"])
        #expect(unreachable.contains("PROJ/B"))
    }

    @Test func `The repository clears once the token can read it again`() async {
        await provider.set(unavailableTagRepos: ["proj/a"])
        await round()

        await provider.set(unavailableTagRepos: [])
        await nextRound()

        #expect(await engine.unreachableRepos()[account.id] == nil)
    }

    @Test func `A failed tag fetch keeps the last known list`() async {
        await provider.set(unavailableTagRepos: ["proj/a"])
        await round()

        await provider.set(tagError: .network("kapot"))
        await nextRound()

        #expect(await engine.unreachableRepos()[account.id]?.repos == ["Proj/A"])
    }

    @Test func `Turning tags and branches off forgets the repositories`() async {
        await provider.set(unavailableTagRepos: ["proj/a"])
        await provider.set(branchFetch: BranchFetch(heads: [], unavailableRepos: ["proj/b"]))
        await round()

        var quiet = account
        let prsOnly = WatchSet(prs: true, tags: false, branches: false)
        quiet.repoWatch = ["Proj/A": prsOnly, "proj/b": prsOnly]
        clock.advance(max(PollEngine.tagInterval, PollEngine.branchInterval))
        await round([quiet])

        #expect(await engine.unreachableRepos()[account.id] == nil)
    }

    @Test func `A removed account is forgotten`() async {
        await provider.set(unavailableTagRepos: ["proj/a"])
        await round()

        await round([])

        #expect(await engine.unreachableRepos().isEmpty)
    }
}
