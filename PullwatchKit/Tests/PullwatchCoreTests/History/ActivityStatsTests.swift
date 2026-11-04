import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct ActivityStatsTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func pr(_ number: Int, repo: String = "P/api", author: String = "ana", created: Date, merged: Date? = nil,
                    state: PRState? = nil) -> PullRequest {
        .fixture(repo: repo, number: number, authorName: author, createdAt: created,
                 state: state ?? (merged == nil ? .open : .merged), closedAt: merged)
    }

    private func history(_ prs: [PullRequest]) -> History {
        var history = History()
        history.add(pullRequests: prs, tags: [.fixture(repo: "P/api", name: "v1")], at: date(2026, 10, 31))
        return history
    }

    private var now: Date { date(2026, 10, 31) }

    @Test func monthlyBucketsCountOpenedByCreatedAndMergedByClosed() {
        let stats = ActivityStats.compute(history: history([
            pr(1, created: date(2026, 10, 2), merged: date(2026, 10, 4)),
            pr(2, created: date(2026, 9, 28), merged: date(2026, 10, 1)),
            pr(3, created: date(2026, 9, 10)),
            pr(4, created: date(2026, 9, 11), merged: date(2026, 9, 12), state: .closed),
        ]), period: .month, filter: ActivityFilter(), now: now, calendar: calendar)
        #expect(stats.buckets.count == 12)
        #expect(stats.buckets.last?.start == calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        #expect(stats.buckets.last.map { [$0.opened, $0.merged] } == [1, 2])
        #expect(stats.buckets.dropLast().last.map { [$0.opened, $0.merged] } == [3, 0])
        #expect(stats.openedThisPeriod == 1)
        #expect(stats.mergedThisPeriod == 2)
    }

    @Test func weeksStartOnMondayAndYearsGoBackFive() {
        let h = history([pr(1, created: date(2026, 10, 26))])
        let weeks = ActivityStats.compute(history: h, period: .week, filter: ActivityFilter(), now: now, calendar: calendar)
        #expect(weeks.buckets.count == 12)
        #expect(weeks.buckets.last?.start == calendar.date(from: DateComponents(year: 2026, month: 10, day: 26)))
        #expect(weeks.openedThisPeriod == 1)
        let years = ActivityStats.compute(history: h, period: .year, filter: ActivityFilter(), now: now, calendar: calendar)
        #expect(years.buckets.count == 5)
        #expect(years.buckets.first?.start == calendar.date(from: DateComponents(year: 2022, month: 1, day: 1)))
    }

    @Test func medianLeadTimeOverMergedInRange() {
        let stats = ActivityStats.compute(history: history([
            pr(1, created: date(2026, 10, 1), merged: date(2026, 10, 2)),
            pr(2, created: date(2026, 10, 1), merged: date(2026, 10, 4)),
            pr(3, created: date(2026, 10, 1), merged: date(2026, 10, 11)),
        ]), period: .month, filter: ActivityFilter(), now: now, calendar: calendar)
        #expect(stats.medianLeadTime == TimeInterval(3 * 86_400))
    }

    @Test func rankingsAndActiveAuthorsAndBotFilter() {
        let h = history([
            pr(1, author: "ana", created: date(2026, 10, 1)),
            pr(2, author: "ana", created: date(2026, 9, 1)),
            pr(3, repo: "P/web", author: "bob", created: date(2026, 10, 2)),
            pr(4, repo: "P/web", author: "dependabot[bot]", created: date(2026, 10, 3)),
            pr(5, repo: "P/web", author: "dependabot[bot]", created: date(2026, 10, 4)),
            pr(6, repo: "P/web", author: "dependabot[bot]", created: date(2026, 10, 5)),
        ])
        let all = ActivityStats.compute(history: h, period: .month, filter: ActivityFilter(hideBots: false), now: now, calendar: calendar)
        #expect(all.authors.map(\.name) == ["dependabot[bot]", "ana", "bob"])
        #expect(all.activeAuthors == 3)
        let noBots = ActivityStats.compute(history: h, period: .month, filter: ActivityFilter(), now: now, calendar: calendar)
        #expect(noBots.authors.map(\.name) == ["ana", "bob"])
        #expect(noBots.authors.map(\.count) == [2, 1])
        #expect(noBots.repos.map(\.name) == ["P/api", "P/web"])
        #expect(noBots.activeAuthors == 2)
    }

    @Test func filtersOnGroupAuthorAndRepo() {
        let h = history([
            pr(1, repo: "FerroHEALTH/ehr", author: "ana", created: date(2026, 10, 1)),
            pr(2, repo: "Code24/engine", author: "ana", created: date(2026, 10, 1)),
            pr(3, repo: "FerroHEALTH/ehr", author: "bob", created: date(2026, 10, 1)),
        ])
        let group = HistoryGroup.ID(accountId: fixedAccountId, project: "FerroHEALTH")
        func opened(_ filter: ActivityFilter) -> Int {
            ActivityStats.compute(history: h, period: .month, filter: filter, now: now, calendar: calendar).openedThisPeriod
        }
        #expect(opened(ActivityFilter(group: group)) == 2)
        #expect(opened(ActivityFilter(author: "ana")) == 2)
        #expect(opened(ActivityFilter(group: group, author: "ana")) == 1)
        #expect(opened(ActivityFilter(repoId: "\(fixedAccountId.uuidString)/Code24/engine")) == 1)
    }

    @Test func closedWithoutMergeAndDraftsCountPerBucketAndInTotal() throws {
        let stats = ActivityStats.compute(history: history([
            // Oktober: twee geopend, waarvan één een open draft; één gesloten zonder merge.
            .fixture(repo: "P/api", number: 1, authorName: "ana", isDraft: true, createdAt: date(2026, 10, 2)),
            .fixture(repo: "P/api", number: 2, authorName: "ana", createdAt: date(2026, 10, 3), state: .closed,
                     closedAt: date(2026, 10, 5)),
            // September geopend, oktober gesloten zonder merge: telt in twee periodes.
            .fixture(repo: "P/web", number: 3, authorName: "bob", createdAt: date(2026, 9, 20), state: .closed,
                     closedAt: date(2026, 10, 1)),
            // Een draft uit augustus is nog open; een gesloten draft telt als gesloten.
            .fixture(repo: "P/web", number: 4, authorName: "bob", isDraft: true, createdAt: date(2026, 8, 1)),
            .fixture(repo: "P/web", number: 5, authorName: "bob", isDraft: true, createdAt: date(2026, 9, 2), state: .closed,
                     closedAt: date(2026, 9, 3)),
            pr(6, author: "ana", created: date(2026, 9, 4), merged: date(2026, 10, 6)),
        ]), period: .month, filter: ActivityFilter(), now: now, calendar: calendar)
        let october = try #require(stats.buckets.last)
        #expect([october.opened, october.drafts, october.openedReady, october.merged, october.closed] == [2, 1, 1, 1, 2] as [Int])
        let september = try #require(stats.buckets.dropLast().last)
        #expect([september.opened, september.drafts, september.merged, september.closed] == [3, 0, 0, 1] as [Int])
        #expect(stats.buckets.dropLast(2).last.map { [$0.opened, $0.drafts] } == [1, 1])
        #expect(stats.closedThisPeriod == 2)
        #expect(stats.mergedThisPeriod == 1)
        #expect(stats.openDrafts == 2)
        #expect(stats.authorStates["ana"] == PRStateCounts(open: 0, draft: 1, merged: 1, closed: 1))
        #expect(stats.authorStates["bob"] == PRStateCounts(draft: 1, closed: 2))
        #expect(stats.repoStates["P/web"] == PRStateCounts(draft: 1, closed: 2))
    }

    @Test func openDraftsFollowTheFilter() {
        let h = history([
            .fixture(repo: "P/api", number: 1, authorName: "ana", isDraft: true, createdAt: date(2026, 10, 2)),
            .fixture(repo: "P/web", number: 2, authorName: "bob", isDraft: true, createdAt: date(2026, 10, 2)),
            .fixture(repo: "P/web", number: 3, authorName: "dependabot[bot]", isDraft: true, createdAt: date(2026, 10, 2)),
        ])
        func drafts(_ filter: ActivityFilter) -> Int {
            ActivityStats.compute(history: h, period: .month, filter: filter, now: now, calendar: calendar).openDrafts
        }
        #expect(drafts(ActivityFilter()) == 2)
        #expect(drafts(ActivityFilter(hideBots: false)) == 3)
        #expect(drafts(ActivityFilter(author: "bob")) == 1)
    }

    @Test func outsideTheRangeDoesNotCount() {
        let stats = ActivityStats.compute(history: history([pr(1, created: date(2025, 1, 1), merged: date(2025, 1, 2))]),
                                          period: .month, filter: ActivityFilter(), now: now, calendar: calendar)
        #expect(stats.buckets.allSatisfy { $0.opened == 0 && $0.merged == 0 && $0.closed == 0 && $0.drafts == 0 })
        #expect(stats.authors.isEmpty)
        #expect(stats.medianLeadTime == nil)
    }
}
