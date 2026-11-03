import Foundation

package final class TestClock: @unchecked Sendable {
    package init() {}

    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_760_000_000)

    package var now: Date { lock.withLock { current } }

    package func advance(_ seconds: TimeInterval) {
        lock.withLock { current += seconds }
    }
}
