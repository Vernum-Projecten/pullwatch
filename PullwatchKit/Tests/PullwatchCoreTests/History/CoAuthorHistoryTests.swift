import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Co-auteurs in de geschiedenis, in oude bestanden en in de statistieken.
@Suite struct CoAuthorHistoryTests {
    let mona = Person(name: "Mona Lisa", login: "mona", email: "mona@example.com",
                      avatarURL: URL(string: "https://avatars.example.com/mona"))
    let jan = Person(name: "Jan", email: "jan@example.com")

    @Test func oldHistoryWithoutCoAuthorsStillLoads() throws {
        let json = #"""
        {"items":[{"detectedAt":0,"isRead":true,"entry":{"pullRequest":{"_0":{
          "accountId":"00000000-0000-0000-0000-000000000001","repo":"P/api","number":7,"title":"Old",
          "authorId":"ana","authorName":"ana","isDraft":false,"createdAt":0,
          "webURL":"https://example.com/7","state":"merged","closedAt":10}}}}]}
        """#
        let history = try JSONDecoder().decode(History.self, from: Data(json.utf8))
        guard case .pullRequest(let pr) = try #require(history.items.first).entry else {
            Issue.record("geen PR")
            return
        }
        #expect(pr.coAuthors.isEmpty)
        #expect(pr.revision == nil)
        #expect(pr.number == 7)
    }

    @Test func coAuthorsRoundTripThroughJSON() throws {
        var history = History()
        history.add(pullRequests: [.fixture(number: 1, coAuthors: [mona, jan], revision: "r1")], tags: [], at: Date(timeIntervalSince1970: 0))
        let data = try JSONEncoder().encode(history)
        #expect(try JSONDecoder().decode(History.self, from: data) == history)
    }

    @Test func oldSeenStateWithoutCoAuthorsStillLoads() throws {
        let json = #"{"seen":{},"lastSettings":{}}"#
        #expect(try JSONDecoder().decode(SeenState.self, from: Data(json.utf8)).coAuthors.isEmpty)
    }

    @Test func mergeUpdatesCoAuthorsButKeepsThemWhenTheSyncHasNone() {
        var history = History()
        history.merge(synced: [.fixture(number: 1)])
        let added = history.merge(synced: [.fixture(number: 1, coAuthors: [mona])])
        #expect(added)
        #expect(history.items.first?.entry.coAuthors == [mona])

        let emptied = history.merge(synced: [.fixture(number: 1)])
        #expect(!emptied)
        #expect(history.items.first?.entry.coAuthors == [mona])

        let replaced = history.merge(synced: [.fixture(number: 1, coAuthors: [jan])])
        #expect(replaced)
        #expect(history.items.first?.entry.coAuthors == [jan])
    }

    @Test func searchFindsCoAuthors() {
        var history = History()
        history.add(pullRequests: [.fixture(number: 1, coAuthors: [mona]), .fixture(number: 2)], tags: [], at: Date())
        #expect(history.search("mona", kind: .pullRequest).map(\.entry.dedupKey) == [PullRequest.fixture(number: 1).dedupKey])
        #expect(history.search("Lisa", kind: .pullRequest).count == 1)
    }

    @Test func contributorNamesUseTheLogin() {
        let pr = PullRequest.fixture(authorName: "ana", coAuthors: [mona, jan])
        #expect(pr.contributorNames == ["ana", "mona", "Jan"])
    }

    @Test func statisticsCountCoAuthorsOnlyWhenAskedTo() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12))!
        var history = History()
        history.add(pullRequests: [
            .fixture(number: 1, authorName: "ana", createdAt: now - 3600, coAuthors: [mona]),
            .fixture(number: 2, authorName: "mona", createdAt: now - 7200),
            .fixture(number: 3, authorName: "ana", createdAt: now - 9000,
                     coAuthors: [Person(name: "helper[bot]", login: "helper[bot]")]),
        ], tags: [], at: now)

        let plain = ActivityStats.compute(history: history, period: .month, filter: ActivityFilter(), now: now, calendar: calendar)
        #expect(plain.authors == [RankedName(name: "ana", count: 2), RankedName(name: "mona", count: 1)])
        #expect(plain.activeAuthors == 2)

        let counted = ActivityFilter(countCoAuthors: true)
        let withCoAuthors = ActivityStats.compute(history: history, period: .month, filter: counted, now: now, calendar: calendar)
        #expect(withCoAuthors.authors == [RankedName(name: "ana", count: 2), RankedName(name: "mona", count: 2)])
        #expect(withCoAuthors.openedThisPeriod == 3)

        let onlyMona = ActivityStats.compute(
            history: history, period: .month, filter: ActivityFilter(author: "mona", countCoAuthors: true), now: now, calendar: calendar
        )
        #expect(onlyMona.openedThisPeriod == 2)
        let onlyMonaAsAuthor = ActivityStats.compute(
            history: history, period: .month, filter: ActivityFilter(author: "mona"), now: now, calendar: calendar
        )
        #expect(onlyMonaAsAuthor.openedThisPeriod == 1)
    }
}
