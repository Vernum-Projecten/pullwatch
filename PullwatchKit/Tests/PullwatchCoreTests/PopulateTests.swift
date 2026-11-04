import Foundation
import Synchronization
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Een nieuw account vult zijn schermen in één poll: PR's en tags standaard gevolgd, bestaande
/// tags stil in de geschiedenis, en één status voor wat er loopt.
@Suite struct PopulateTests {
    let day: TimeInterval = 24 * 3600

    private func engine(_ account: Account, clock: TestClock = TestClock()) -> (PollEngine, MockProvider, TestClock) {
        let provider = MockProvider()
        return (PollEngine(makeProvider: { _ in provider }, store: nil, now: { clock.now }), provider, clock)
    }

    private func datedTag(_ account: Account, repo: String = "proj/a", name: String, at date: Date) -> PullwatchCore.Tag {
        PullwatchCore.Tag(
            accountId: account.id, repo: repo, name: name, authorName: nil,
            webURL: URL(string: "https://example.com/\(repo)/tag/\(name)")!, createdAt: date
        )
    }

    // MARK: - Standaard volgen

    /// Een nieuw account haalt niets op tot je repo's kiest; wie "PR's en tags" als standaard
    /// kiest, volgt elke repo met beide.
    @Test func newAccountFollowsNothingUntilYouChoose() {
        var account = Account(kind: .gitHub, organization: "octo", authMethod: .gitHubApp)
        #expect(account.newRepoDefault == .none)
        #expect(account.watch(for: "octo/any") == .none)
        #expect(!account.followsTagsByDefault)

        account.newRepoDefault = .prsAndTags
        #expect(account.watch(for: "octo/any") == .both)
        #expect(account.followsTagsByDefault)
    }

    @Test func storedConfigKeepsItsDefault() throws {
        let prs = #"{"id":"00000000-0000-0000-0000-000000000009","kind":"gitHub","organization":"o","authMethod":"pat","repoWatch":{},"newRepoDefault":"prs","includeDrafts":false,"hideOwn":true}"#
        let account = try JSONDecoder().decode(Account.self, from: Data(prs.utf8))
        #expect(account.newRepoDefault == .prs)
        #expect(!account.followsTagsByDefault)

        let none = prs.replacingOccurrences(of: #""newRepoDefault":"prs""#, with: #""newRepoDefault":"none""#)
        #expect(try JSONDecoder().decode(Account.self, from: Data(none.utf8)).newRepoDefault == .none)

        // Zonder het veld (heel oude config): alleen PR's, zoals vroeger.
        let missing = prs.replacingOccurrences(of: #","newRepoDefault":"prs""#, with: "")
        #expect(try JSONDecoder().decode(Account.self, from: Data(missing.utf8)).newRepoDefault == .prs)
    }

    @Test(arguments: NewRepoDefault.allCases)
    func newDefaultRoundTrips(choice: NewRepoDefault) throws {
        let account = Account(kind: .gitHub, organization: "octo", authMethod: .gitHubApp, newRepoDefault: choice)
        let decoded = try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(account))
        #expect(decoded.newRepoDefault == choice)
    }

    @Test func tagReposComeFromTheProviderListWhenTagsAreTheDefault() {
        let account = Account.fixture(repoWatch: ["proj/off": .none, "proj/prs": .prs], newRepoDefault: .prsAndTags)
        #expect(account.tagRepos(available: ["proj/a", "proj/off", "proj/prs", "Proj/B"]) == ["proj/a", "Proj/B"])
    }

    @Test func defaultTagsFetchTagsOfEveryListedRepo() async {
        let account = Account.fixture(newRepoDefault: .prsAndTags)
        let (engine, provider, clock) = engine(account)
        await provider.set(repos: ["proj/a", "proj/b"])
        let v1 = Tag.fixture(accountId: account.id, repo: "proj/b", name: "v1")
        await provider.set(tags: [v1])
        let first = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
        #expect(first.newTags.isEmpty)
        #expect(first.tagRepos[account.id] == ["proj/a", "proj/b"])

        let v2 = Tag.fixture(accountId: account.id, repo: "proj/b", name: "v2")
        await provider.set(tags: [v1, v2])
        clock.advance(900)
        #expect(await engine.poll(accounts: [account], interval: 120, retention: .oneYear).newTags == [v2])
    }

    // MARK: - Tags in de geschiedenis

    @Test func firstTagPollBackfillsDatedTagsWithoutNotifying() async {
        let account = Account.fixture(repoWatch: ["proj/a": .both])
        let (engine, provider, clock) = engine(account)
        let recent = datedTag(account, name: "v2", at: clock.now - 10 * day)
        let old = datedTag(account, name: "v1", at: clock.now - 400 * day)
        await provider.set(tags: [Tag.fixture(accountId: account.id, repo: "proj/a", name: "v1"),
                                  Tag.fixture(accountId: account.id, repo: "proj/a", name: "v2")])
        await provider.set(datedTags: [recent, old])

        let first = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
        #expect(first.newTags.isEmpty)
        // Alleen binnen de bewaartermijn.
        #expect(first.syncedTags == [recent])

        // Daarna geen backfill meer, en een bestaande tag wordt niet alsnog gemeld.
        clock.advance(900)
        let second = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
        #expect(second.syncedTags.isEmpty)
        #expect(second.newTags.isEmpty)
        #expect(await provider.datedTagRepos == ["proj/a"])
    }

    @Test func backfillFailureStillSeedsSilently() async {
        let account = Account.fixture(repoWatch: ["proj/a": .both])
        let (engine, provider, clock) = engine(account)
        let v1 = Tag.fixture(accountId: account.id, repo: "proj/a", name: "v1")
        await provider.set(tags: [v1])
        await provider.set(datedTagError: .server(status: 502))
        let first = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
        #expect(first.newTags.isEmpty)
        #expect(first.syncedTags.isEmpty)

        let v2 = Tag.fixture(accountId: account.id, repo: "proj/a", name: "v2")
        await provider.set(tags: [v1, v2])
        clock.advance(900)
        #expect(await engine.poll(accounts: [account], interval: 120, retention: .oneYear).newTags == [v2])
    }

    @Test func unavailableRepoIsBackfilledOnceReachable() async {
        let account = Account.fixture(repoWatch: ["proj/a": .both])
        let (engine, provider, clock) = engine(account)
        let tag = datedTag(account, name: "v1", at: clock.now - day)
        await provider.set(tags: [Tag.fixture(accountId: account.id, repo: "proj/a", name: "v1")])
        await provider.set(datedTags: [tag])
        await provider.set(unavailableTagRepos: ["proj/a"])
        let first = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
        #expect(first.syncedTags.isEmpty)
        #expect(await provider.datedTagRepos.isEmpty)

        await provider.set(unavailableTagRepos: [])
        clock.advance(900)
        let second = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
        #expect(second.newTags.isEmpty)
        #expect(second.syncedTags == [tag])
    }

    @Test func historyAddsSyncedTagsAsRead() {
        let account = Account.fixture()
        let now = Date.testStart
        let older = datedTag(account, name: "v1", at: now - 5 * day)
        let newer = datedTag(account, name: "v2", at: now - day)
        let ancient = datedTag(account, name: "v0", at: now - 100 * day)
        let undated = Tag.fixture(accountId: account.id, repo: "proj/a", name: "v9")
        var history = History()
        let added = history.merge(syncedTags: [older, newer, ancient, undated], notBefore: now - 61 * day)
        #expect(added)
        #expect(history.items.map(\.entry.title) == ["v2", "v1"])
        #expect(history.items.allSatisfy { $0.isRead })
        #expect(history.items.first?.detectedAt == newer.createdAt)
        #expect(history.unreadCount == 0)

        // Een tag die er al staat (bv. gemeld en ongelezen) blijft zoals hij is.
        var notified = History()
        notified.add(pullRequests: [], tags: [Tag.fixture(accountId: account.id, repo: "proj/a", name: "v2")], at: now)
        let addedAgain = notified.merge(syncedTags: [newer])
        #expect(!addedAgain)
        #expect(notified.unreadCount == 1)
    }

    // MARK: - Voortgang en status

    @Test func pollReportsProgressAndTheFirstSyncAccount() async {
        let account = Account.fixture()
        let (engine, _, clock) = engine(account)
        let reports = Mutex<[PollProgress]>([])
        #expect(await engine.pendingFirstSync(accounts: [account], retention: .oneYear) == [account.id])
        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear) { progress in
            reports.withLock { $0.append(progress) }
        }
        #expect(reports.withLock { $0 } == [
            PollProgress(done: 0, total: 1, firstSyncAccount: account.displayName),
            PollProgress(done: 1, total: 1, firstSyncAccount: account.displayName),
        ])
        #expect(await engine.pendingFirstSync(accounts: [account], retention: .oneYear).isEmpty)

        reports.withLock { $0 = [] }
        clock.advance(900)
        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear) { progress in
            reports.withLock { $0.append(progress) }
        }
        #expect(reports.withLock { $0 }.last == PollProgress(done: 1, total: 1))
    }

    @Test func cancelledRefetchKeepsTheIncrementalSync() async throws {
        let account = Account.fixture()
        let (engine, provider, clock) = engine(account)
        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
        let firstSync = clock.now

        await engine.resetHistorySync()
        #expect(await engine.pendingFirstSync(accounts: [account], retention: .oneYear) == [account.id])
        await engine.cancelHistoryResync()
        #expect(await engine.pendingFirstSync(accounts: [account], retention: .oneYear).isEmpty)

        clock.advance(900)
        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
        let since = try #require(await provider.lastSyncSince)
        #expect(since == firstSync - PollEngine.syncOverlap)
    }

    @Test func cancelAfterAResyncKeepsTheNewMark() async throws {
        let account = Account.fixture()
        let (engine, provider, clock) = engine(account)
        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
        await engine.resetHistorySync()
        clock.advance(60)
        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
        let resynced = clock.now
        await engine.cancelHistoryResync()

        clock.advance(900)
        _ = await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
        #expect(try #require(await provider.lastSyncSince) == resynced - PollEngine.syncOverlap)
    }

    @Test func statusPicksTheMostTellingWork() {
        let poll = PollProgress(done: 1, total: 3)
        let firstSync = PollProgress(done: 0, total: 2, firstSyncAccount: "@octo op GitHub")

        #expect(SyncStatus.current(poll: nil, firstSyncPending: false, refetch: nil, versions: nil, failure: nil) == .idle)
        #expect(SyncStatus.current(poll: poll, firstSyncPending: false, refetch: nil, versions: nil, failure: nil)
                == .syncing(done: 1, total: 3, what: .accounts))
        #expect(SyncStatus.current(poll: firstSync, firstSyncPending: true, refetch: nil, versions: (2, 9), failure: nil)
                == .syncing(done: 0, total: 2, what: .firstSync(account: "@octo op GitHub")))
        // Wacht een eerste sync nog op zijn beurt, dan telt hij als lopend, zonder aantallen.
        #expect(SyncStatus.current(poll: nil, firstSyncPending: true, refetch: nil, versions: (2, 9), failure: nil)
                == .syncing(done: 0, total: 0, what: .firstSync(account: nil)))
        #expect(SyncStatus.current(poll: poll, firstSyncPending: false, refetch: nil, versions: (2, 9), failure: nil)
                == .syncing(done: 2, total: 9, what: .versions))
        #expect(SyncStatus.current(poll: nil, firstSyncPending: false, refetch: nil, versions: nil, checkingRepo: "octo/api", failure: nil)
                == .syncing(done: 0, total: 0, what: .repoCheck("octo/api")))
        #expect(SyncStatus.current(poll: firstSync, firstSyncPending: true, refetch: (1, 2), versions: (2, 9), failure: "x")
                == .syncing(done: 1, total: 2, what: .refetch))
        // Een fout alleen als er niets meer loopt.
        #expect(SyncStatus.current(poll: poll, firstSyncPending: false, refetch: nil, versions: nil, failure: "offline").isSyncing)
        #expect(SyncStatus.current(poll: nil, firstSyncPending: false, refetch: nil, versions: nil, failure: "offline") == .failed("offline"))
    }

    @Test func onlyRefetchAndVersionChecksCanStopAndOnlyLongWorkShowsTheBar() {
        #expect(SyncWork.refetch.isCancellable)
        #expect(SyncWork.versions.isCancellable)
        #expect(!SyncWork.firstSync(account: nil).isCancellable)
        #expect(!SyncWork.accounts.isCancellable)
        #expect(!SyncWork.repoCheck("a").isCancellable)
        #expect(!SyncWork.accounts.showsActivityBar)
        #expect(SyncWork.firstSync(account: nil).showsActivityBar)
        #expect(SyncWork.versions.showsActivityBar)
    }
}
