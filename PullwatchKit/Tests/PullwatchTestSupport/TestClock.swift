import Foundation
import Synchronization

package extension Date {
    /// Het vaste "nu" van de tests: het begin van `TestClock` en de standaard van de fixtures.
    static let testStart = Date(timeIntervalSince1970: 1_760_000_000)
}

/// Een klok die alleen verder loopt als een test dat zegt.
package final class TestClock: Sendable {
    package init() {}

    private let current = Mutex(Date.testStart)

    package var now: Date { current.withLock { $0 } }

    package func advance(_ seconds: TimeInterval) {
        current.withLock { $0 += seconds }
    }
}
