import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct ReleaseHistoryTests {
    let release = ReleaseInfo(
        title: "Versie 2",
        authorLogin: "mona",
        isPrerelease: true,
        url: URL(string: "https://github.com/acme/api/releases/tag/v2")!
    )

    @Test func tagFromOldHistoryDecodesWithoutReleaseOrAvatar() throws {
        let json = #"""
        {"items":[{"entry":{"tag":{"_0":{"accountId":"\#(fixedAccountId.uuidString)","repo":"acme/api","name":"v1",
          "webURL":"https://github.com/acme/api/releases/tag/v1"}}},"detectedAt":0,"isRead":true}]}
        """#
        let history = try JSONDecoder().decode(History.self, from: Data(json.utf8))

        guard case .tag(let tag) = try #require(history.items.first).entry else { Issue.record("geen tag"); return }
        #expect(tag.name == "v1")
        #expect(tag.release == nil && tag.authorAvatarURL == nil && tag.authorName == nil && tag.createdAt == nil)
    }

    @Test func tagWithReleaseSurvivesARoundTrip() throws {
        var history = History()
        history.add(pullRequests: [], tags: [Tag.fixture(name: "v2", release: release)], at: Date(timeIntervalSince1970: 0))

        let data = try JSONEncoder().encode(history)

        #expect(try JSONDecoder().decode(History.self, from: data) == history)
    }

    @Test func releaseOfASeenTagReplacesItsRowInsteadOfAddingOne() {
        var history = History()
        let plain = Tag.fixture(name: "v2")
        history.add(pullRequests: [], tags: [plain, Tag.fixture(name: "v3")], at: Date(timeIntervalSince1970: 0))
        history.markAllRead()

        history.add(pullRequests: [], tags: [Tag.fixture(name: "v2", release: release)], at: Date(timeIntervalSince1970: 60))

        #expect(history.items.count == 2)
        guard case .tag(let tag) = history.items[0].entry else { Issue.record("geen tag"); return }
        #expect(tag.release == release)
        #expect(!history.items[0].isRead)
    }

    @Test func updateFillsInAuthorAndReleaseOfKnownTagsOnly() {
        var history = History()
        let old = Tag(accountId: fixedAccountId, repo: "acme/api", name: "v1", authorName: nil,
                      webURL: URL(string: "https://github.com/acme/api/releases/tag/v1")!,
                      createdAt: Date(timeIntervalSince1970: 100))
        history.add(pullRequests: [], tags: [old], at: Date(timeIntervalSince1970: 200))
        history.markAllRead()
        let fresh = Tag(accountId: fixedAccountId, repo: "acme/api", name: "v1", authorName: "rubentalstra",
                        authorAvatarURL: URL(string: "https://avatars.githubusercontent.com/u/1"),
                        webURL: release.url, release: release)
        let unknown = Tag.fixture(repo: "acme/api", name: "v9")

        let changed = history.update(tags: [fresh, unknown])

        #expect(changed)
        #expect(history.items.count == 1)
        #expect(history.items[0].isRead)
        guard case .tag(let tag) = history.items[0].entry else { Issue.record("geen tag"); return }
        #expect(tag.authorName == "rubentalstra")
        #expect(tag.release == release)
        #expect(tag.webURL == release.url)
        #expect(tag.createdAt == Date(timeIntervalSince1970: 100)) // een bekende datum blijft staan
        let again = history.update(tags: [fresh])
        #expect(!again)
    }

    @Test func searchFindsTheReleaseTitle() {
        var history = History()
        history.add(pullRequests: [], tags: [Tag.fixture(name: "v2", release: release), Tag.fixture(name: "v1")], at: Date())

        #expect(history.search("versie", kind: .tag).map(\.entry.title) == ["v2"])
    }

    @Test func releaseTitleIsHiddenWhenItOnlyRepeatsTheTag() {
        var same = release
        same.title = "v2"
        #expect(Tag.fixture(name: "v2", release: same).releaseTitle == nil)
        same.title = "  "
        #expect(Tag.fixture(name: "v2", release: same).releaseTitle == nil)
        #expect(Tag.fixture(name: "v2", release: release).releaseTitle == "Versie 2")
    }

    @Test func releasesAndTagsAreSummarisedApart() {
        let releases = (1...4).map { Tag.fixture(repo: "p/r", name: "v\($0)", release: ReleaseInfo(title: "R\($0)", url: release.url)) }
        let plain = Tag.fixture(repo: "p/r", name: "nightly")

        let plans = NotificationPlanner.plan(pullRequests: [], tags: releases + [plain])

        #expect(plans == [
            .summary(kind: .release, count: 4, lines: ["p/r: R1", "p/r: R2", "p/r: R3"]),
            .tag(plain),
        ])
    }

    @Test func oldSeenStateDecodesWithoutFingerprints() throws {
        let json = #"{"seen":{},"lastSettings":{},"tagSeeded":{"a:proj/x":0}}"#
        let state = try JSONDecoder().decode(SeenState.self, from: Data(json.utf8))
        #expect(state.tagFingerprints.isEmpty)
        #expect(state.tagSeeded.count == 1)
    }

    @Test func fingerprintsLeaveWithTheirSeededRepo() {
        var state = SeenState()
        state.tagSeeded = ["a:proj/x": Date(timeIntervalSince1970: 0), "a:proj/y": Date()]
        state.tagFingerprints = ["a:proj/x": "1", "a:proj/y": "2"]

        state.prune(now: Date())

        #expect(state.tagFingerprints == ["a:proj/y": "2"])
    }
}
