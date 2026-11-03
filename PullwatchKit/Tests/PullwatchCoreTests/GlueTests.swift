import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct GlueTests {
    @Test func backoffDoublesPerFailureAndCaps() {
        #expect(Backoff.delay(baseInterval: 120, consecutiveFailures: 0) == 120)
        #expect(Backoff.delay(baseInterval: 120, consecutiveFailures: 1) == 240)
        #expect(Backoff.delay(baseInterval: 120, consecutiveFailures: 2) == 480)
        #expect(Backoff.delay(baseInterval: 120, consecutiveFailures: 3) == 900)
        #expect(Backoff.delay(baseInterval: 120, consecutiveFailures: 50) == 900)
    }
}
