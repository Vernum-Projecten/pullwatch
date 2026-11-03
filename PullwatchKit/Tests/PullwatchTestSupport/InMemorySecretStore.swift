import Foundation
import PullwatchCore

package final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    package init() {}
    package func read(account: String) throws -> String? { lock.withLock { values[account] } }
    package func write(_ secret: String, account: String) throws { lock.withLock { values[account] = secret } }
    package func delete(account: String) throws { _ = lock.withLock { values.removeValue(forKey: account) } }
}
