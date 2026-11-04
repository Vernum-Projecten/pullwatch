import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct ActivityStatsCacheTests {
    let now = Date.testStart

    private func history(_ count: Int) -> History {
        var history = History()
        let prs = (0..<count).map { PullRequest.fixture(number: $0 + 1, createdAt: now - 3600) }
        history.add(pullRequests: prs, tags: [], at: now)
        return history
    }

    @Test func `A fresh result stays until its lifetime is over`() {
        var cache = ActivityStatsCache()
        let first = cache.stats(history: history(1), period: .month, filter: ActivityFilter(), now: now)
        let cached = cache.stats(history: history(3), period: .month, filter: ActivityFilter(), now: now + 599)
        #expect(first.openedThisPeriod == 1)
        #expect(cached.openedThisPeriod == 1)
    }

    @Test func `After its lifetime the result is computed again`() {
        var cache = ActivityStatsCache()
        _ = cache.stats(history: history(1), period: .month, filter: ActivityFilter(), now: now)
        let fresh = cache.stats(history: history(3), period: .month, filter: ActivityFilter(), now: now + ActivityStatsCache.lifetime)
        #expect(fresh.openedThisPeriod == 3)
    }

    @Test func `Each period and filter has its own result`() {
        var cache = ActivityStatsCache()
        _ = cache.stats(history: history(1), period: .month, filter: ActivityFilter(), now: now)
        let other = cache.stats(history: history(3), period: .year, filter: ActivityFilter(), now: now)
        #expect(other.openedThisPeriod == 3)
    }

    @Test func `Removing all computes again`() {
        var cache = ActivityStatsCache()
        _ = cache.stats(history: history(1), period: .month, filter: ActivityFilter(), now: now)
        cache.removeAll()
        let fresh = cache.stats(history: history(3), period: .month, filter: ActivityFilter(), now: now)
        #expect(fresh.openedThisPeriod == 3)
    }
}
