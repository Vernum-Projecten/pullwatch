import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// De wachttijd na mislukte polls.
@Suite struct BackoffTests {
    @Test func backoffDoublesPerFailureAndCaps() {
        #expect(Backoff.delay(baseInterval: 120, consecutiveFailures: 0) == 120)
        #expect(Backoff.delay(baseInterval: 120, consecutiveFailures: 1) == 240)
        #expect(Backoff.delay(baseInterval: 120, consecutiveFailures: 2) == 480)
        #expect(Backoff.delay(baseInterval: 120, consecutiveFailures: 3) == 900)
        #expect(Backoff.delay(baseInterval: 120, consecutiveFailures: 50) == 900)
    }
}
