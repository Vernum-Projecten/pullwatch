import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct ChecksFailedNotificationTests {
    let pr = PullRequest.fixture(number: 7, authorId: "me", revision: "r1")

    @Test func `The notification is off by default, also in old settings`() throws {
        #expect(!NotificationSettings().checksFailed)
        let old = try JSONDecoder().decode(NotificationSettings.self, from: Data(#"{"pullRequests":true}"#.utf8))
        #expect(!old.checksFailed)
        #expect(NotificationKind.switchable.contains(.checksFailed))
    }

    @Test func `Only planned when the switch is on`() {
        let off = NotificationPlanner.plan(pullRequests: [], tags: [], failedChecks: [pr])
        var settings = NotificationSettings()
        settings.checksFailed = true
        let on = NotificationPlanner.plan(pullRequests: [], tags: [], failedChecks: [pr], settings: settings)

        #expect(off.isEmpty)
        #expect(on == [.single(.checksFailed(pr))])
    }

    @Test func `Also when the repository follows new pull requests quietly`() {
        var account = Account.fixture(id: fixedAccountId)
        account.setWatch(WatchSet(prs: true, tags: false, notifyPRs: false), for: pr.repo)
        var settings = NotificationSettings()
        settings.checksFailed = true

        let plans = NotificationPlanner.plan(pullRequests: [pr], tags: [], failedChecks: [pr], settings: settings, accounts: [account])

        #expect(plans == [.single(.checksFailed(pr))])
    }

    @Test func `It has its own identifier and belongs to the pull requests`() {
        let item = RepositoryItem.checksFailed(pr)
        #expect(item.kind == .checksFailed)
        #expect(item.notificationIdentifier == pr.dedupKey + ":checks")
        #expect(item.historyKey == pr.dedupKey)
        #expect(item.watchKind == .pullRequests)
        #expect(NotificationImportance.of(.checksFailed).level == .active)
        #expect(NotificationImportance.of(.checksFailed, quiet: true).level == .passive)
    }
}
