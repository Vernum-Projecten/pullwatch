import Foundation
import Testing
@testable import PullwatchCore

@Suite struct WatchKindTests {
    @Test func followingAKindTurnsItsNotificationOn() {
        var watch = WatchSet(prs: false, tags: false, notifyPRs: false, notifyTags: false, notifyCompleted: false)
        watch[follows: .tags] = true
        #expect(watch.tags && watch.notifyTags)
        #expect(!watch.prs)
    }

    @Test func mergedNeedsPullRequests() {
        var watch = WatchSet.none
        watch[follows: .merged] = true
        #expect(watch.completed && watch.prs && watch.notifyPRs && watch.notifyCompleted)

        watch[follows: .pullRequests] = false
        #expect(!watch.prs && !watch.completed)
    }

    @Test func notificationsAreSeparateFromFollowing() {
        var watch = WatchSet.both
        watch[notifies: .pullRequests] = false
        watch[notifies: .merged] = false
        #expect(watch.prs && !watch.notifyPRs && !watch.notifyCompleted)
        for kind in WatchKind.allCases { #expect(watch[follows: kind] == (kind != .merged)) }
    }

    @Test func newRepoDefaultsStillDecode() throws {
        for raw in ["none", "prs", "prsAndTags"] {
            let decoded = try JSONDecoder().decode(NewRepoDefault.self, from: Data("\"\(raw)\"".utf8))
            #expect(decoded.rawValue == raw)
        }
    }
}
