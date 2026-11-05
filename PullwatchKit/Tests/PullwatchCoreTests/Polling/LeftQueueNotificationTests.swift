import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// De melding "Uit de rij": een open PR die de vorige poll in de rij zag (merge queue, merge
/// train, auto-merge, auto-complete) en die er nu uit is zonder te mergen.
@Suite struct LeftQueueNotificationTests {
    let account = Account.fixture()
    let provider = MockProvider()
    let clock = TestClock()

    var pr: PullRequest { PullRequest.fixture(accountId: account.id, number: 7) }

    func queued(_ pr: PullRequest, _ kind: MergeQueueEntry.Kind = .mergeQueue) -> PullRequest {
        var pr = pr
        pr.mergeQueue = MergeQueueEntry(kind: kind)
        return pr
    }

    func makeEngine(store: JSONFileStore<SeenState>? = nil) -> PollEngine {
        let clock = clock
        let provider = provider
        return PollEngine(makeProvider: { _ in provider }, store: store, now: { clock.now })
    }

    func poll(_ engine: PollEngine) async -> PollResult {
        clock.advance(120)
        return await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
    }

    // MARK: - Instelling en planner

    @Test func `The notification is on by default, also in old settings`() throws {
        #expect(NotificationSettings().leftQueue)
        let old = try JSONDecoder().decode(NotificationSettings.self, from: Data(#"{"pullRequests":true}"#.utf8))
        #expect(old.leftQueue)
        #expect(NotificationKind.switchable.contains(.leftQueue))
        var settings = NotificationSettings()
        settings[.leftQueue] = false
        #expect(!settings.leftQueue)
    }

    @Test func `Only planned when the switch is on`() {
        var settings = NotificationSettings()
        let on = NotificationPlanner.plan(pullRequests: [], tags: [], leftQueue: [pr], settings: settings)
        settings.leftQueue = false
        let off = NotificationPlanner.plan(pullRequests: [], tags: [], leftQueue: [pr], settings: settings)

        #expect(on == [.single(.leftQueue(pr))])
        #expect(off.isEmpty)
    }

    @Test func `Not when the repository follows new pull requests quietly`() {
        var account = Account.fixture(id: fixedAccountId)
        account.setWatch(WatchSet(prs: true, tags: false, notifyPRs: false), for: pr.repo)
        let quiet = PullRequest.fixture(number: 7)

        let plans = NotificationPlanner.plan(pullRequests: [], tags: [], leftQueue: [quiet], accounts: [account])

        #expect(plans.isEmpty)
    }

    @Test func `It has its own identifier and belongs to the pull requests`() {
        let item = RepositoryItem.leftQueue(pr)
        #expect(item.kind == .leftQueue)
        #expect(item.notificationIdentifier == pr.dedupKey + ":queue")
        #expect(item.historyKey == pr.dedupKey)
        #expect(item.watchKind == .pullRequests)
        #expect(NotificationImportance.of(.leftQueue).level == .active)
        #expect(NotificationImportance.of(.leftQueue, quiet: true).level == .passive)
    }

    // MARK: - PollEngine

    @Test(arguments: [MergeQueueEntry.Kind.mergeQueue, .mergeTrain, .autoMerge, .autoComplete])
    func `Queued, then open and not queued, gives one notification`(kind: MergeQueueEntry.Kind) async throws {
        let engine = makeEngine()
        await provider.set(pullRequests: [queued(pr, kind)])
        _ = await poll(engine)
        await provider.set(pullRequests: [pr])

        let result = await poll(engine)
        let again = await poll(engine)

        let left = try #require(result.leftQueue.first)
        #expect(result.leftQueue.count == 1)
        #expect(left.dedupKey == pr.dedupKey)
        #expect(left.leftQueue == MergeQueueExit(kind: kind, at: clock.now - 120))
        #expect(again.leftQueue.isEmpty)
    }

    @Test func `The reason the service gives comes along`() async {
        let engine = makeEngine()
        await provider.set(pullRequests: [queued(pr)])
        _ = await poll(engine)
        await provider.set(pullRequests: [pr])
        await provider.set(exits: MergeQueueExits(reasons: [pr.dedupKey: "Checks failed"]))

        let result = await poll(engine)

        #expect(result.leftQueue.map(\.leftQueue?.reason) == ["Checks failed"])
        #expect(await provider.exitRequests == [[pr.dedupKey]])
    }

    @Test func `No reason is asked while nothing left the queue`() async {
        let engine = makeEngine()
        await provider.set(pullRequests: [queued(pr)])
        _ = await poll(engine)
        _ = await poll(engine)

        #expect(await provider.exitRequests.isEmpty)
    }

    @Test func `Queued, then merged, gives none`() async {
        let engine = makeEngine()
        await provider.set(pullRequests: [queued(pr)])
        _ = await poll(engine)
        // Gemerged: niet meer in de open lijst.
        await provider.set(pullRequests: [])

        let result = await poll(engine)
        // Een PR die later weer open is zonder rij meldt ook niet: zijn stand is weg.
        await provider.set(pullRequests: [pr])
        let reopened = await poll(engine)

        #expect(result.leftQueue.isEmpty)
        #expect(reopened.leftQueue.isEmpty)
    }

    @Test func `A pull request the service says merged after all gives none`() async {
        let engine = makeEngine()
        await provider.set(pullRequests: [queued(pr)])
        _ = await poll(engine)
        await provider.set(pullRequests: [pr])
        await provider.set(exits: MergeQueueExits(notLeft: [pr.dedupKey]))

        let result = await poll(engine)

        #expect(result.leftQueue.isEmpty)
    }

    @Test func `Queued, then draft, gives none`() async {
        let engine = makeEngine()
        await provider.set(pullRequests: [queued(pr)])
        _ = await poll(engine)
        await provider.set(pullRequests: [PullRequest.fixture(accountId: account.id, number: 7, isDraft: true)])

        let draft = await poll(engine)
        await provider.set(pullRequests: [pr])
        let ready = await poll(engine)

        #expect(draft.leftQueue.isEmpty)
        #expect(ready.leftQueue.isEmpty)
    }

    @Test func `A failed read of the queue keeps the old state and gives none`() async {
        let engine = makeEngine()
        await provider.set(pullRequests: [queued(pr)])
        _ = await poll(engine)
        await provider.set(pullRequests: [pr])
        await provider.set(unreadMergeQueues: [pr.dedupKey])

        let failed = await poll(engine)
        await provider.set(unreadMergeQueues: [])
        let read = await poll(engine)

        #expect(failed.leftQueue.isEmpty)
        #expect(failed.mergeQueues[pr.dedupKey] == nil, "de geschiedenis houdt wat hij had")
        #expect(read.leftQueue.map(\.dedupKey) == [pr.dedupKey])
    }

    @Test func `The first poll after launch gives none without a previous state`() async {
        await provider.set(pullRequests: [pr])

        let first = await poll(makeEngine())

        #expect(first.leftQueue.isEmpty)
    }

    @Test func `The previous state survives a restart`() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileStore<SeenState>(url: directory.appending(path: "seen.json"))
        await provider.set(pullRequests: [queued(pr, .autoMerge)])
        _ = await poll(makeEngine(store: store))
        #expect(try store.load()?.queued[pr.dedupKey]?.kind == .autoMerge)

        await provider.set(pullRequests: [pr])
        let result = await poll(makeEngine(store: store))

        #expect(result.leftQueue.map(\.leftQueue?.kind) == [.autoMerge])
    }

    @Test func `A pull request the list hides gives none`() async {
        let engine = makeEngine()
        // `hideOwn` staat aan in de fixture: een eigen PR staat niet in de lijst.
        let own = PullRequest.fixture(accountId: account.id, number: 8, authorId: "me")
        await provider.set(pullRequests: [queued(own)])
        _ = await poll(engine)
        await provider.set(pullRequests: [own])

        let result = await poll(engine)

        #expect(result.leftQueue.isEmpty)
    }

    // MARK: - Geschiedenis

    func storedPullRequest(_ history: History) throws -> PullRequest {
        let entry = try #require(history.items.first?.entry)
        if case .pullRequest(let pr) = entry { return pr }
        return try #require(nil as PullRequest?, "geen PR in de geschiedenis")
    }

    @Test func `The history keeps that it left the queue until it is queued again`() throws {
        var history = History()
        history.add(pullRequests: [queued(pr)], tags: [], at: .testStart)
        var left = pr
        left.leftQueue = MergeQueueExit(kind: .mergeQueue, at: .testStart, reason: "Checks failed")

        let changed = history.update(leftQueue: [left])
        #expect(changed)
        let stored = try storedPullRequest(history)
        #expect(stored.hasLeftQueue)
        #expect(stored.leftQueue?.reason == "Checks failed")

        let requeuedChanged = history.update(mergeQueues: [pr.dedupKey: MergeQueueEntry(kind: .mergeQueue)])
        #expect(requeuedChanged)
        let requeued = try storedPullRequest(history)
        #expect(requeued.leftQueue == nil)
        #expect(!requeued.hasLeftQueue)
    }
}
