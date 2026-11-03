import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct PollIntervalChoiceTests {
    @Test(arguments: [(45, 60), (60, 60), (100, 120), (200, 120), (250, 300), (700, 600), (800, 900), (5000, 900)])
    func `The interval snaps to the nearest choice`(stored: Int, choice: Int) {
        var config = AppConfig()
        config.pollInterval = stored
        #expect(config.pollIntervalChoice == choice)
    }
}
