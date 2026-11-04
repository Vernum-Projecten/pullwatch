import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct PollEngineCheckTests {
    let account = Account.fixture()
    let provider = MockProvider()
    let clock = TestClock()

    let green = PRChecks.counts(CheckCounts(passed: 7, skipped: 1))
    let running = PRChecks.counts(CheckCounts(passed: 3, pending: 5))
    let red = PRChecks.counts(CheckCounts(passed: 4, failed: 1, pending: 3))

    private func makeEngine() -> PollEngine {
        let clock = clock
        let provider = provider
        return PollEngine(makeProvider: { _ in provider }, store: nil, now: { clock.now })
    }

    private func poll(_ engine: PollEngine, own: Bool = false) async -> PollResult {
        await engine.poll(accounts: [account], interval: 120, retention: .oneYear, checksForOwnPullRequests: own)
    }

    @Test func `An open pull request arrives with its checks`() async {
        let engine = makeEngine()
        _ = await poll(engine)
        let pr = PullRequest.fixture(accountId: account.id, number: 2, revision: "r1")
        await provider.set(pullRequests: [pr])
        await provider.set(checks: [pr.dedupKey: green])
        clock.advance(120)

        let result = await poll(engine)

        #expect(result.newPullRequests.map(\.checks) == [green])
        #expect(result.checks == [pr.dedupKey: green])
    }

    @Test func `With the CI checks source off a poll asks no checks`() async {
        let engine = makeEngine()
        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear, fetchChecks: false)
        let pr = PullRequest.fixture(accountId: account.id, number: 2, revision: "r1")
        await provider.set(pullRequests: [pr])
        await provider.set(checks: [pr.dedupKey: red])
        clock.advance(120)

        let result = await engine.poll(
            accounts: [account], interval: 120, retention: .oneYear, checksForOwnPullRequests: true, fetchChecks: false
        )

        #expect(await provider.checkRequests.isEmpty)
        #expect(result.checks.isEmpty)
        #expect(result.failedChecks.isEmpty)
        #expect(result.newPullRequests.map(\.checks) == [nil])
    }

    @Test func `Finished checks of an unchanged pull request cost no request`() async {
        let engine = makeEngine()
        let pr = PullRequest.fixture(accountId: account.id, number: 1, revision: "r1")
        await provider.set(pullRequests: [pr])
        await provider.set(checks: [pr.dedupKey: green])

        _ = await poll(engine)
        for _ in 0..<3 {
            clock.advance(120)
            _ = await poll(engine)
        }

        #expect(await provider.checkRequests == [[pr.dedupKey]])
    }

    @Test func `Running checks are asked every poll until they finish`() async {
        let engine = makeEngine()
        let pr = PullRequest.fixture(accountId: account.id, number: 1, revision: "r1")
        await provider.set(pullRequests: [pr])
        await provider.set(checks: [pr.dedupKey: running])
        _ = await poll(engine)
        clock.advance(120)
        _ = await poll(engine)

        await provider.set(checks: [pr.dedupKey: green])
        clock.advance(120)
        let finished = await poll(engine)
        clock.advance(120)
        _ = await poll(engine)

        #expect(await provider.checkRequests.count == 3)
        #expect(finished.checks[pr.dedupKey] == green)
    }

    @Test func `A push asks again`() async {
        let engine = makeEngine()
        let pr = PullRequest.fixture(accountId: account.id, number: 1, revision: "r1")
        await provider.set(pullRequests: [pr])
        await provider.set(checks: [pr.dedupKey: green])
        _ = await poll(engine)

        await provider.set(pullRequests: [PullRequest.fixture(accountId: account.id, number: 1, revision: "r2")])
        clock.advance(120)
        _ = await poll(engine)

        #expect(await provider.checkRequests.count == 2)
    }

    @Test func `Failed checks of an open pull request are asked again now and then`() async {
        let engine = makeEngine()
        let pr = PullRequest.fixture(accountId: account.id, number: 1, revision: "r1")
        await provider.set(pullRequests: [pr])
        await provider.set(checks: [pr.dedupKey: red])
        _ = await poll(engine)
        clock.advance(120)
        _ = await poll(engine)
        #expect(await provider.checkRequests.count == 1)

        clock.advance(PollEngine.failedCheckRefresh)
        _ = await poll(engine)
        #expect(await provider.checkRequests.count == 2)
    }

    @Test func `Without permission it waits an hour before asking again`() async {
        let engine = makeEngine()
        let pr = PullRequest.fixture(accountId: account.id, number: 1, revision: "r1")
        await provider.set(pullRequests: [pr])
        await provider.set(checks: [pr.dedupKey: .needsPermission])
        let first = await poll(engine)
        clock.advance(120)
        _ = await poll(engine)

        #expect(first.checks[pr.dedupKey] == .needsPermission)
        #expect(await provider.checkRequests.count == 1)
        clock.advance(PollEngine.checkPermissionRetry)
        _ = await poll(engine)
        #expect(await provider.checkRequests.count == 2)
    }

    @Test func `Recently merged pull requests get their checks, old and closed ones do not`() async {
        let engine = makeEngine()
        let recent = PullRequest.fixture(accountId: account.id, number: 1, state: .merged, closedAt: clock.now - 3600, revision: "a")
        let old = PullRequest.fixture(accountId: account.id, number: 2, state: .merged, closedAt: clock.now - 30 * 86_400, revision: "b")
        let closed = PullRequest.fixture(accountId: account.id, number: 3, state: .closed, closedAt: clock.now - 3600, revision: "c")
        await provider.set(syncedPullRequests: [recent, old, closed])

        _ = await poll(engine)

        #expect(await provider.checkRequests == [[recent.dedupKey]])
    }

    @Test func `Co-authors and checks share one call`() async {
        let engine = makeEngine()
        let pr = PullRequest.fixture(accountId: account.id, number: 1, revision: "r1")
        await provider.set(pullRequests: [pr])

        _ = await poll(engine)

        #expect(await provider.coAuthorRequests == [[pr.dedupKey]])
        #expect(await provider.checkRequests == [[pr.dedupKey]])
    }

    @Test func `Checks of an older revision are not shown`() async {
        let engine = makeEngine()
        let pr = PullRequest.fixture(accountId: account.id, number: 1, revision: "r1")
        await provider.set(syncedPullRequests: [pr])
        await provider.set(checks: [pr.dedupKey: green])
        _ = await poll(engine)

        // Een push; de provider vindt (nog) geen checks voor de nieuwe commit.
        let pushed = PullRequest.fixture(accountId: account.id, number: 1, revision: "r2")
        await provider.set(syncedPullRequests: [pushed])
        await provider.set(checks: [:])
        clock.advance(PollEngine.tagInterval)
        let result = await poll(engine)

        #expect(result.syncedPullRequests.first?.checks == nil)
    }

    @Test func `Own pull request whose checks turn red is reported once`() async {
        let engine = makeEngine()
        let pr = PullRequest.fixture(accountId: account.id, number: 1, authorId: "me", revision: "r1")
        await provider.set(pullRequests: [pr])
        await provider.set(checks: [pr.dedupKey: running])
        let first = await poll(engine, own: true)

        await provider.set(checks: [pr.dedupKey: red])
        clock.advance(120)
        let second = await poll(engine, own: true)
        clock.advance(PollEngine.failedCheckRefresh)
        let third = await poll(engine, own: true)

        #expect(first.failedChecks.isEmpty)
        #expect(second.failedChecks.map(\.number) == [1])
        #expect(second.failedChecks.first?.checks == red)
        #expect(third.failedChecks.isEmpty)
    }

    @Test func `A pull request seen red the first time stays quiet`() async {
        let engine = makeEngine()
        let pr = PullRequest.fixture(accountId: account.id, number: 1, authorId: "me", revision: "r1")
        await provider.set(pullRequests: [pr])
        await provider.set(checks: [pr.dedupKey: red])

        let result = await poll(engine, own: true)

        #expect(result.failedChecks.isEmpty)
    }

    @Test func `Red checks on a new push of an own pull request are reported again`() async {
        let engine = makeEngine()
        let pr = PullRequest.fixture(accountId: account.id, number: 1, authorId: "me", revision: "r1")
        await provider.set(pullRequests: [pr])
        await provider.set(checks: [pr.dedupKey: red])
        _ = await poll(engine, own: true)

        await provider.set(pullRequests: [PullRequest.fixture(accountId: account.id, number: 1, authorId: "me", revision: "r2")])
        clock.advance(120)
        let result = await poll(engine, own: true)

        #expect(result.failedChecks.map(\.revision) == ["r2"])
    }

    @Test func `Someone else's pull request and the setting off report nothing`() async {
        let engine = makeEngine()
        let theirs = PullRequest.fixture(accountId: account.id, number: 1, authorId: "mona", revision: "r1")
        let mine = PullRequest.fixture(accountId: account.id, number: 2, authorId: "me", revision: "r1")
        await provider.set(pullRequests: [theirs, mine])
        await provider.set(checks: [theirs.dedupKey: running])
        _ = await poll(engine, own: false)

        await provider.set(checks: [theirs.dedupKey: red, mine.dedupKey: red])
        clock.advance(120)
        let result = await poll(engine, own: false)

        #expect(result.failedChecks.isEmpty)
        // Zonder de melding vraagt Pullwatch de checks van eigen PR's niet (die zijn verborgen).
        #expect(await provider.checkRequests.allSatisfy { !$0.contains(mine.dedupKey) })
    }

    @Test func `With the notification on, hidden own pull requests are asked too`() async {
        let engine = makeEngine()
        let mine = PullRequest.fixture(accountId: account.id, number: 2, authorId: "me", revision: "r1")
        await provider.set(pullRequests: [mine])

        _ = await poll(engine, own: true)

        #expect(await provider.checkRequests == [[mine.dedupKey]])
        #expect(await provider.coAuthorRequests.isEmpty)
    }
}

@Suite struct CheckCountsTests {
    @Test(arguments: [
        (CheckCounts(passed: 8), CheckState?.some(.passed)),
        (CheckCounts(passed: 6, skipped: 2), .passed),
        (CheckCounts(passed: 4, failed: 1, pending: 3), .failed),
        (CheckCounts(passed: 3, pending: 5), .pending),
        (CheckCounts(), nil),
    ])
    func `State follows the worst check`(_ counts: CheckCounts, _ state: CheckState?) {
        #expect(counts.state == state)
    }

    @Test func `Skipped checks count as passed`() {
        let counts = CheckCounts([.passed, .skipped, .failed, .pending])
        #expect(counts.succeeded == 2)
        #expect(counts.total == 4)
    }

    @Test func `Checks survive a round trip through JSON`() throws {
        for checks in [PRChecks.counts(CheckCounts(passed: 1, failed: 2)), .needsPermission] {
            let pr = PullRequest.fixture(revision: "r").with(checks: checks)
            let decoded = try JSONDecoder().decode(PullRequest.self, from: JSONEncoder().encode(pr))
            #expect(decoded.checks == checks)
        }
    }

    @Test func `Old JSON without checks still decodes`() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(PullRequest.fixture())) as? [String: Any])
        json["checks"] = nil
        let decoded = try JSONDecoder().decode(PullRequest.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.checks == nil)
    }

    @Test func `History takes new checks without moving or marking anything`() {
        var history = History()
        let pr = PullRequest.fixture(number: 1)
        history.add(pullRequests: [pr], tags: [], at: Date(timeIntervalSince1970: 0))
        let checks = PRChecks.counts(CheckCounts(passed: 2))

        let first = history.update(checks: [pr.dedupKey: checks])
        let second = history.update(checks: [pr.dedupKey: checks])
        #expect(first)
        #expect(!second)
        #expect(history.items.first?.entry.checks == checks)
        #expect(history.items.first?.isRead == false)
    }

    @Test func `A synced pull request without checks keeps the stored ones`() {
        var history = History()
        let checks = PRChecks.counts(CheckCounts(passed: 2))
        history.merge(synced: [PullRequest.fixture(number: 1).with(checks: checks)])
        history.merge(synced: [PullRequest.fixture(number: 1, title: "Renamed")])
        #expect(history.items.first?.entry.checks == checks)
        #expect(history.items.first?.entry.title == "Renamed")
    }
}

private extension PullRequest {
    func with(checks: PRChecks?) -> PullRequest {
        var pr = self
        pr.checks = checks
        return pr
    }
}
