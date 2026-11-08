import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct PollEngineCoAuthorTests {
    let mona = Person(name: "Mona", login: "mona", email: "mona@example.com")
    let hubot = Person(name: "Hubot", login: "hubot")

    private func engine(_ provider: MockProvider, clock: TestClock, store: JSONFileStore<SeenState>? = nil) -> PollEngine {
        PollEngine(makeProvider: { _ in provider }, store: store, now: { clock.now })
    }

    @Test func newPullRequestArrivesWithItsCoAuthors() async {
        let account = Account.fixture()
        let provider = MockProvider()
        let clock = TestClock()
        let engine = engine(provider, clock: clock)
        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)

        let pr = PullRequest.fixture(accountId: account.id, number: 2, revision: "r1")
        await provider.set(pullRequests: [pr])
        await provider.set(coAuthors: [pr.dedupKey: [mona]])
        clock.advance(120)
        let result = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)

        #expect(result.newPullRequests.map(\.coAuthors) == [[mona]])
    }

    @Test func unchangedPullRequestCostsNoExtraCall() async {
        let account = Account.fixture()
        let provider = MockProvider()
        let clock = TestClock()
        let engine = engine(provider, clock: clock)
        let pr = PullRequest.fixture(accountId: account.id, number: 1, revision: "r1")
        await provider.set(pullRequests: [pr])
        await provider.set(coAuthors: [pr.dedupKey: [mona]])

        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
        for _ in 0..<3 {
            clock.advance(120)
            _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
        }

        #expect(await provider.coAuthorRequests == [[pr.dedupKey]])
    }

    @Test func pullRequestWithoutCoAuthorsIsAlsoAskedOnlyOnce() async {
        let account = Account.fixture()
        let provider = MockProvider()
        let clock = TestClock()
        let engine = engine(provider, clock: clock)
        let pr = PullRequest.fixture(accountId: account.id, number: 1, revision: "r1")
        await provider.set(pullRequests: [pr])

        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
        clock.advance(120)
        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)

        #expect(await provider.coAuthorRequests.count == 1)
    }

    @Test func changedRevisionFetchesAgain() async {
        let account = Account.fixture()
        let provider = MockProvider()
        let clock = TestClock()
        let engine = engine(provider, clock: clock)
        let pr = PullRequest.fixture(accountId: account.id, number: 1, revision: "r1")
        await provider.set(pullRequests: [pr])
        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)

        await provider.set(pullRequests: [PullRequest.fixture(accountId: account.id, number: 1, revision: "r2")])
        clock.advance(120)
        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)

        #expect(await provider.coAuthorRequests == [[pr.dedupKey], [pr.dedupKey]])
    }

    @Test func syncedPullRequestsCarryStoredCoAuthorsAndOneBatchCoversOpenAndSynced() async {
        let account = Account.fixture()
        let provider = MockProvider()
        let clock = TestClock()
        let engine = engine(provider, clock: clock)
        let open = PullRequest.fixture(accountId: account.id, number: 1, revision: "a")
        let merged = PullRequest.fixture(accountId: account.id, number: 2, state: .merged, closedAt: clock.now, revision: "b")
        await provider.set(pullRequests: [open])
        await provider.set(syncedPullRequests: [open, merged])
        await provider.set(coAuthors: [open.dedupKey: [mona], merged.dedupKey: [hubot]])

        let result = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)

        #expect(await provider.coAuthorRequests == [[open.dedupKey, merged.dedupKey]])
        #expect(Dictionary(uniqueKeysWithValues: result.syncedPullRequests.map { ($0.number, $0.coAuthors) }) == [1: [mona], 2: [hubot]])
    }

    @Test func hiddenPullRequestsAreNotAsked() async {
        let account = Account.fixture(hideOwn: true)
        let provider = MockProvider()
        let clock = TestClock()
        let engine = engine(provider, clock: clock)
        await provider.set(pullRequests: [PullRequest.fixture(accountId: account.id, number: 1, authorId: "me")])

        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)

        #expect(await provider.coAuthorRequests.isEmpty)
    }

    @Test func failedFetchDoesNotFailTheAccountAndIsRetried() async {
        let account = Account.fixture()
        let provider = MockProvider()
        let clock = TestClock()
        let engine = engine(provider, clock: clock)
        let pr = PullRequest.fixture(accountId: account.id, number: 1, revision: "r1")
        await provider.set(pullRequests: [pr])
        await provider.set(coAuthorError: .server(status: 502))

        let first = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
        #expect(first.statuses[account.id] == .ok(lastPoll: clock.now))

        await provider.set(coAuthorError: nil)
        clock.advance(120)
        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
        #expect(await provider.coAuthorRequests.count == 2)
    }

    @Test func atMostTheLimitPerPollNewestFirst() async {
        let account = Account.fixture()
        let provider = MockProvider()
        let clock = TestClock()
        let engine = engine(provider, clock: clock)
        let prs = (1...(PollEngine.coAuthorLimit + 5)).map {
            PullRequest.fixture(accountId: account.id, number: $0, createdAt: Date(timeIntervalSince1970: Double($0) * 1000), revision: "r")
        }
        await provider.set(pullRequests: prs)

        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
        clock.advance(120)
        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)

        let requests = await provider.coAuthorRequests
        #expect(requests.map(\.count) == [PollEngine.coAuthorLimit, 5])
        #expect(requests.first?.first == prs.last?.dedupKey)
    }

    /// Nieuwe drafts houden de co-auteurs en checks van oudere PR's die klaar zijn voor review niet op.
    @Test func `Pull requests ready for review go before newer drafts`() async {
        let account = Account.fixture()
        let provider = MockProvider()
        let clock = TestClock()
        let engine = engine(provider, clock: clock)
        let ready = (1...5).map {
            PullRequest.fixture(accountId: account.id, number: $0, createdAt: Date(timeIntervalSince1970: Double($0) * 1000), revision: "r")
        }
        let drafts = (6...(PollEngine.coAuthorLimit + 5)).map {
            PullRequest.fixture(accountId: account.id, number: $0, isDraft: true, createdAt: Date(timeIntervalSince1970: Double($0) * 1000), revision: "r")
        }
        await provider.set(pullRequests: ready + drafts)

        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)

        let first = await provider.coAuthorRequests.first ?? []
        #expect(first.count == PollEngine.coAuthorLimit)
        #expect(Array(first.prefix(5)) == ready.reversed().map(\.dedupKey))
    }

    @Test func storedCoAuthorsSurviveARestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileStore<SeenState>(url: directory.appending(path: "seen.json"))
        let account = Account.fixture()
        let provider = MockProvider()
        let clock = TestClock()
        let pr = PullRequest.fixture(accountId: account.id, number: 1, revision: "r1")
        await provider.set(pullRequests: [pr])
        await provider.set(coAuthors: [pr.dedupKey: [mona]])
        _ = await engine(provider, clock: clock, store: store).poll(accounts: [account], interval: 120, retention: .oneYear)

        let restarted = engine(provider, clock: clock, store: store)
        clock.advance(120)
        _ = await restarted.poll(accounts: [account], interval: 120, retention: .oneYear)

        #expect(await provider.coAuthorRequests.count == 1)
        #expect(try store.load()?.coAuthors[pr.dedupKey]?.people == [mona])
    }
}
