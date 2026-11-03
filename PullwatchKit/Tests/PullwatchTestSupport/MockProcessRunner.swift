import Foundation
import PullwatchCore

package final class MockProcessRunner: ProcessRunner, @unchecked Sendable {
    package init() {}

    private let lock = NSLock()
    private var _output = ProcessOutput(status: 0, stdout: "", stderr: "")
    private var _calls: [(URL, [String])] = []

    package var output: ProcessOutput {
        get { lock.withLock { _output } }
        set { lock.withLock { _output = newValue } }
    }

    package var calls: [(URL, [String])] { lock.withLock { _calls } }

    package func run(_ executable: URL, _ arguments: [String]) async throws -> ProcessOutput {
        lock.withLock {
            _calls.append((executable, arguments))
            return _output
        }
    }
}
