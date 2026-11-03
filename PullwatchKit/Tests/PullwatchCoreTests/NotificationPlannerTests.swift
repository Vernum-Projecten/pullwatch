import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct NotificationPlannerTests {
    private let release = ReleaseInfo(title: "Lente", url: URL(string: "https://example.com/r")!)

    @Test func upToTheCapEveryNewPullRequestGetsItsOwnNotification() {
        let prs = (1...NotificationPlanner.cap).map { PullRequest.fixture(number: $0) }
        #expect(NotificationPlanner.plan(pullRequests: prs, tags: []) == prs.map { .single(.pullRequest($0)) })
    }

    @Test func aboveTheCapOneSummaryPerRepositoryInFirstSeenOrder() {
        let api = (1...15).map { PullRequest.fixture(repo: "p/api", number: $0) }
        let web = (1...5).map { PullRequest.fixture(repo: "p/web", number: $0) }
        let lone = PullRequest.fixture(repo: "p/lone", number: 1)
        let plan = NotificationPlanner.plan(pullRequests: [api[0], lone] + web + api.dropFirst(), tags: [])
        #expect(plan == [
            .summary(RepositoryKey(accountId: fixedAccountId, repo: "p/api"), api.map { .pullRequest($0) }),
            .single(.pullRequest(lone)),
            .summary(RepositoryKey(accountId: fixedAccountId, repo: "p/web"), web.map { .pullRequest($0) }),
        ])
    }

    @Test func theCapCountsEveryKindTogether() {
        let prs = (1...10).map { PullRequest.fixture(repo: "p/r", number: $0) }
        let tags = (1...11).map { Tag.fixture(repo: "p/r", name: "v\($0)") }
        let plan = NotificationPlanner.plan(pullRequests: prs, tags: tags)
        #expect(plan.count == 1)
        guard case .summary(let key, let items) = plan.first else {
            Issue.record("geen samenvatting")
            return
        }
        #expect(key.threadIdentifier == "\(fixedAccountId.uuidString)/p/r")
        #expect(items.count == 21)
    }

    @Test func emptyInputPlansNothing() {
        #expect(NotificationPlanner.plan(pullRequests: [], tags: []).isEmpty)
    }

    @Test func pullRequestsThenReleasesThenTagsThenMerged() {
        let pr = PullRequest.fixture(number: 1)
        let tag = Tag.fixture(name: "v1")
        let released = Tag.fixture(name: "v2", release: release)
        let merged = PullRequest.fixture(number: 2, state: .merged)
        #expect(NotificationPlanner.plan(pullRequests: [pr], tags: [tag, released], completed: [merged])
            == [.single(.pullRequest(pr)), .single(.tag(released)), .single(.tag(tag)), .single(.merged(merged))])
    }

    @Test func aKindThatIsOffInSettingsIsLeftOut() {
        let pr = PullRequest.fixture(number: 1)
        let tag = Tag.fixture(name: "v1")
        let released = Tag.fixture(name: "v2", release: release)
        let merged = PullRequest.fixture(number: 2, state: .merged)
        var settings = NotificationSettings()
        settings.tags = false
        settings.merged = false
        #expect(NotificationPlanner.plan(pullRequests: [pr], tags: [tag, released], completed: [merged], settings: settings)
            == [.single(.pullRequest(pr)), .single(.tag(released))])
        settings.pullRequests = false
        settings.releases = false
        #expect(NotificationPlanner.plan(pullRequests: [pr], tags: [tag, released], completed: [merged], settings: settings).isEmpty)
    }

    @Test func perRepositoryChoicesStillApply() {
        let account = Account(
            id: fixedAccountId, kind: .gitHub, organization: "p", authMethod: .pat,
            repoWatch: ["p/quiet": WatchSet(prs: true, tags: true, notifyPRs: false)]
        )
        let quiet = PullRequest.fixture(repo: "p/quiet", number: 1)
        let loud = PullRequest.fixture(repo: "p/loud", number: 2)
        #expect(NotificationPlanner.plan(pullRequests: [quiet, loud], tags: [], accounts: [account]) == [.single(.pullRequest(loud))])
    }

    @Test func itemsKnowTheirKindKeysAndWatchKind() {
        let pr = PullRequest.fixture(repo: "P/Api", number: 7)
        #expect(RepositoryItem.pullRequest(pr).kind == .pullRequest)
        #expect(RepositoryItem.merged(pr).kind == .merged)
        #expect(RepositoryItem.tag(.fixture(name: "v1")).kind == .tag)
        #expect(RepositoryItem.tag(.fixture(name: "v1", release: release)).kind == .release)
        #expect(RepositoryItem.pullRequest(pr).notificationIdentifier == pr.dedupKey)
        #expect(RepositoryItem.merged(pr).notificationIdentifier == pr.dedupKey + ":completed")
        #expect(RepositoryItem.merged(pr).historyKey == pr.dedupKey)
        #expect(RepositoryItem.merged(pr).watchKind == .merged)
        #expect(RepositoryItem.pullRequest(pr).watchKind == .pullRequests)
        #expect(RepositoryItem.tag(.fixture(name: "v1", release: release)).watchKind == .tags)
        // Hoofdletters maken geen andere stapel.
        #expect(RepositoryItem.pullRequest(pr).repository.threadIdentifier
            == RepositoryKey(accountId: fixedAccountId, repo: "p/api").threadIdentifier)
    }

    @Test func cappedWorksForAnyItem() {
        let items = (1...3).map { "x\($0)" }
        let key = RepositoryKey(accountId: nil, repo: "r")
        #expect(NotificationPlanner.capped(items, repository: { _ in key }, cap: 3) == items.map { .single($0) })
        #expect(NotificationPlanner.capped(items, repository: { _ in key }, cap: 2) == [.summary(key, items)])
        #expect(key.threadIdentifier == "-/r")
    }
}

@Suite struct NotificationImportanceTests {
    @Test func newPullRequestsAndReleasesComeWithABanner() {
        #expect(NotificationImportance.of(.pullRequest).level == .active)
        #expect(NotificationImportance.of(.release).level == .active)
        #expect(NotificationImportance.of(.pullRequest).playsSound)
    }

    @Test func tagsMergedAndNewVersionsArePassiveAndSilent() {
        for kind in [NotificationKind.tag, .merged, .packageUpdate, .appUpdate] {
            #expect(NotificationImportance.of(kind).level == .passive)
            #expect(!NotificationImportance.of(kind).playsSound)
        }
    }

    @Test func vulnerabilitiesLeadAndTheWorstLeadsMost() {
        let critical = NotificationImportance.of(.vulnerability, severityRank: 4)
        let high = NotificationImportance.of(.vulnerability, severityRank: 3)
        let unknown = NotificationImportance.of(.vulnerability)
        #expect(critical.level == .active)
        #expect(critical.relevance > high.relevance)
        #expect(high.relevance > unknown.relevance)
        #expect(unknown.relevance > NotificationImportance.of(.pullRequest).relevance)
        #expect(critical.relevance <= 1)
        #expect(NotificationImportance.of(.securityAlert, severityRank: 9).relevance == critical.relevance)
    }

    @Test func quietHoursMakeEverythingPassiveAndSilent() {
        for kind in NotificationKind.allCases {
            let quiet = NotificationImportance.of(kind, severityRank: 4, quiet: true)
            #expect(quiet.level == .passive)
            #expect(!quiet.playsSound)
            #expect(quiet.relevance == NotificationImportance.of(kind, severityRank: 4).relevance)
        }
    }

    @Test func aSummaryIsAsImportantAsItsStrongestItem() {
        let all = [NotificationImportance.of(.tag), .of(.pullRequest), .of(.merged)]
        #expect(NotificationImportance.strongest(all) == .of(.pullRequest))
        #expect(NotificationImportance.strongest([]) == nil)
    }
}

@Suite struct QuietHoursTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return calendar
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: hour, minute: minute))!
    }

    @Test func offIsNeverQuiet() {
        #expect(!QuietHours(isOn: false).contains(at(23), calendar: calendar))
    }

    @Test func overnightWrapsPastMidnight() {
        let quiet = QuietHours(isOn: true, start: 22 * 60, end: 7 * 60)
        #expect(quiet.contains(at(22), calendar: calendar))
        #expect(quiet.contains(at(23, 59), calendar: calendar))
        #expect(quiet.contains(at(0), calendar: calendar))
        #expect(quiet.contains(at(6, 59), calendar: calendar))
        #expect(!quiet.contains(at(7), calendar: calendar))
        #expect(!quiet.contains(at(12), calendar: calendar))
        #expect(!quiet.contains(at(21, 59), calendar: calendar))
    }

    @Test func withinOneDay() {
        let quiet = QuietHours(isOn: true, start: 12 * 60, end: 13 * 60 + 30)
        #expect(quiet.contains(at(12), calendar: calendar))
        #expect(quiet.contains(at(13, 29), calendar: calendar))
        #expect(!quiet.contains(at(13, 30), calendar: calendar))
        #expect(!quiet.contains(at(11, 59), calendar: calendar))
    }

    @Test func equalStartAndEndIsNeverQuietAndValuesAreClamped() {
        #expect(!QuietHours(isOn: true, start: 600, end: 600).contains(at(10), calendar: calendar))
        let clamped = QuietHours(isOn: true, start: -5, end: 99_999)
        #expect(clamped.start == 0)
        #expect(clamped.end == 24 * 60 - 1)
    }
}

@Suite struct NotificationSettingsTests {
    @Test func defaultsMatchTheIssue() {
        let settings = NotificationSettings()
        #expect(settings.pullRequests && settings.merged && settings.releases && settings.tags)
        #expect(settings.vulnerabilities && settings.packageUpdates && settings.onlyUpdatesYouCanTake)
        #expect(!settings.securityAlerts)
        #expect(!settings.quietHours.isOn)
        #expect(settings.dockBadge && settings.menuBarDot)
    }

    @Test func subscriptReadsAndWritesEachSwitchableKind() {
        var settings = NotificationSettings()
        for kind in NotificationKind.switchable {
            let before = settings[kind]
            settings[kind] = !before
            #expect(settings[kind] == !before)
        }
        settings[.appUpdate] = false
        settings[.account] = false
        #expect(settings[.appUpdate] && settings[.account])
    }

    @Test func oldConfigCarriesTheThreeGeneralSwitchesOver() throws {
        let json = #"{"accounts":[],"pollInterval":120,"notifyPackageUpdates":false,"notifyOnlyUpdatesYouCanTake":false,"notifySecurityAlerts":true}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(!config.notifications.packageUpdates)
        #expect(!config.notifications.onlyUpdatesYouCanTake)
        #expect(config.notifications.securityAlerts)
        #expect(config.notifications.pullRequests)
        #expect(!config.notifications.quietHours.isOn)
    }

    @Test func newConfigRoundTripsAndStillWritesTheOldKeys() throws {
        var config = AppConfig()
        config.notifications.tags = false
        config.notifications.securityAlerts = true
        config.notifications.quietHours = QuietHours(isOn: true, start: 60, end: 120)
        config.notifications.menuBarDot = false
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(AppConfig.self, from: data) == config)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["notifySecurityAlerts"] as? Bool == true)
        #expect(object["notifyPackageUpdates"] as? Bool == true)
    }

    @Test func partialSettingsFillInDefaults() throws {
        let settings = try JSONDecoder().decode(NotificationSettings.self, from: Data(#"{"tags":false,"quietHours":{"isOn":true}}"#.utf8))
        #expect(!settings.tags)
        #expect(settings.pullRequests)
        #expect(settings.quietHours == QuietHours(isOn: true))
    }

    @Test func legacyInitializerArgumentsWinOverNotifications() {
        var notifications = NotificationSettings()
        notifications.securityAlerts = true
        #expect(AppConfig(notifications: notifications).notifySecurityAlerts)
        #expect(!AppConfig(notifySecurityAlerts: false, notifications: notifications).notifySecurityAlerts)
    }
}

@Suite struct SilentRepoTests {
    @Test func silencedKindsAreDroppedPerRepo() {
        let account = Account(
            id: fixedAccountId, kind: .gitHub, organization: "p", authMethod: .pat,
            repoWatch: [
                "p/quiet": WatchSet(prs: true, tags: true, completed: true, notifyPRs: false, notifyCompleted: false),
                "p/loud": .both,
            ]
        )
        let prs = [PullRequest.fixture(repo: "p/quiet", number: 1), PullRequest.fixture(repo: "p/loud", number: 2)]
        let tags = [Tag.fixture(repo: "p/quiet", name: "v1")]

        let audible = NotificationPlanner.audible(pullRequests: prs, tags: tags, completed: prs, accounts: [account])

        #expect(audible.pullRequests.map(\.repo) == ["p/loud"])
        #expect(audible.tags.map(\.repo) == ["p/quiet"])
        #expect(audible.completed.map(\.repo) == ["p/loud"])
    }

    @Test func oldWatchSetJSONNotifiesEverything() throws {
        let watch = try JSONDecoder().decode(WatchSet.self, from: Data(#"{"prs":true,"tags":false}"#.utf8))
        #expect(watch.notifyPRs && watch.notifyTags && watch.notifyCompleted)
    }
}
