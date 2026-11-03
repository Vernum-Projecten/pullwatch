import Foundation
import Synchronization

package final class TestClock: Sendable {
    package init() {}

    private let current = Mutex(Date(timeIntervalSince1970: 1_760_000_000))

    package var now: Date { current.withLock { $0 } }

    package func advance(_ seconds: TimeInterval) {
        current.withLock { $0 += seconds }
    }
}
