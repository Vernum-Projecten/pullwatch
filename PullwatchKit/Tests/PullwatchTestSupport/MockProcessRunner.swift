import Foundation
import PullwatchCore
import Synchronization

package final class MockProcessRunner: ProcessRunner {
    package init() {}

    private struct State {
        var output = ProcessOutput(status: 0, stdout: "", stderr: "")
        var calls: [(URL, [String])] = []
    }

    private let state = Mutex(State())

    package var output: ProcessOutput {
        get { state.withLock { $0.output } }
        set { state.withLock { $0.output = newValue } }
    }

    package var calls: [(URL, [String])] { state.withLock { $0.calls } }

    package func run(_ executable: URL, _ arguments: [String]) async throws -> ProcessOutput {
        state.withLock {
            $0.calls.append((executable, arguments))
            return $0.output
        }
    }
}
