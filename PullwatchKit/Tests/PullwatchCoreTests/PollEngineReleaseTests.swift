import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Releases bij tags en het overslaan van repo's die niet veranderden (vingerafdrukken).
@Suite struct PollEngineReleaseTests {
    private struct Harness {
        let clock = TestClock()
        let provider = MockProvider()
        let engine: PollEngine

        init() {
            let clock = clock
            let provider = provider
            engine = PollEngine(makeProvider: { _ in provider }, store: nil, now: { clock.now })
        }

        func poll(_ account: Account) async -> PollResult {
            await engine.poll(accounts: [account], interval: 120, retention: .oneYear)
        }

        /// Naar de volgende tag-poll.
        func nextTagPoll(_ account: Account) async -> PollResult {
            clock.advance(PollEngine.tagInterval)
            return await poll(account)
        }
    }

    let account = Account.fixture(repoWatch: ["proj/a": .both])

    func release(_ tag: String, title: String = "Release", prerelease: Bool = false) -> ReleaseInfo {
        ReleaseInfo(title: title, authorLogin: "mona", isPrerelease: prerelease, url: URL(string: "https://example.com/release/\(tag)")!)
    }

    @Test func releaseOfAKnownTagNotifiesOnceAsTheSameTag() async {
        let h = Harness()
        let v1 = Tag.fixture(accountId: account.id, repo: "proj/a", name: "v1")
        await h.provider.set(tags: [v1])
        await h.provider.set(fingerprints: ["proj/a": "1"])
        _ = await h.poll(account)
        let v2 = Tag.fixture(accountId: account.id, repo: "proj/a", name: "v2")
        await h.provider.set(tags: [v1, v2])
        await h.provider.set(fingerprints: ["proj/a": "2"])
        #expect(await h.nextTagPoll(account).newTags == [v2])

        let released = Tag.fixture(accountId: account.id, repo: "proj/a", name: "v2", release: release("v2"))
        await h.provider.set(tags: [v1, released])
        await h.provider.set(fingerprints: ["proj/a": "3"])
        let result = await h.nextTagPoll(account)

        #expect(result.newTags == [released])
        #expect(result.newTags.first?.dedupKey == v2.dedupKey)
        #expect(result.updatedTags == [v1])
        await h.provider.set(fingerprints: ["proj/a": "4"])
        #expect(await h.nextTagPoll(account).newTags.isEmpty)
    }

    @Test func newTagWithReleaseNotifiesOnce() async {
        let h = Harness()
        await h.provider.set(tags: [])
        await h.provider.set(fingerprints: ["proj/a": "0"])
        _ = await h.poll(account)
        let v1 = Tag.fixture(accountId: account.id, repo: "proj/a", name: "v1", release: release("v1", prerelease: true))
        await h.provider.set(tags: [v1])
        await h.provider.set(fingerprints: ["proj/a": "1"])

        #expect(await h.nextTagPoll(account).newTags == [v1])
        await h.provider.set(fingerprints: ["proj/a": "2"])
        #expect(await h.nextTagPoll(account).newTags.isEmpty)
    }

    @Test func releasesAlreadyThereAfterAnUpdateStaySilent() async {
        let h = Harness()
        let v1 = Tag.fixture(accountId: account.id, repo: "proj/a", name: "v1")
        await h.provider.set(tags: [v1])
        _ = await h.poll(account) // een versie zonder vingerafdrukken seedde de repo al
        let released = Tag.fixture(accountId: account.id, repo: "proj/a", name: "v1", release: release("v1"))
        await h.provider.set(tags: [released])
        await h.provider.set(fingerprints: ["proj/a": "1"])

        let result = await h.nextTagPoll(account)

        #expect(result.newTags.isEmpty)
        #expect(result.updatedTags == [released])
    }

    @Test func unchangedRepoIsSkippedAndItsTagsStaySeen() async {
        let h = Harness()
        let v1 = Tag.fixture(accountId: account.id, repo: "proj/a", name: "v1")
        await h.provider.set(tags: [v1])
        await h.provider.set(fingerprints: ["proj/a": "1"])
        _ = await h.poll(account)
        #expect(await h.provider.lastUnchanged.isEmpty) // nog niet geseed: alles ophalen

        // Ruim een maand niets veranderd: prune mag v1 niet vergeten.
        for _ in 0..<(40 * 96) {
            h.clock.advance(PollEngine.tagInterval)
            let result = await h.poll(account)
            #expect(result.newTags.isEmpty && result.updatedTags.isEmpty)
        }
        #expect(await h.provider.lastUnchanged == ["proj/a": "1"])

        let v2 = Tag.fixture(accountId: account.id, repo: "proj/a", name: "v2")
        await h.provider.set(tags: [v1, v2])
        await h.provider.set(fingerprints: ["proj/a": "2"])
        #expect(await h.nextTagPoll(account).newTags == [v2])
    }

    @Test func firstTagPollTakesDatesFromTheFetchedTagsWithoutAnExtraRequest() async {
        let h = Harness()
        let dated = Tag.fixture(accountId: account.id, repo: "proj/a", name: "v1", createdAt: h.clock.now - 3600, release: release("v1"))
        await h.provider.set(tags: [dated])

        let result = await h.poll(account)

        #expect(result.syncedTags == [dated])
        #expect(await h.provider.datedTagRepos.isEmpty)
        #expect(result.newTags.isEmpty)
    }
}
