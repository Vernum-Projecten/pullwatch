import Foundation
import PullwatchCore
import Synchronization

package final class InMemorySecretStore: SecretStore {
    private let values = Mutex<[String: String]>([:])
    package init() {}
    package func read(account: String) throws -> String? { values.withLock { $0[account] } }
    package func write(_ secret: String, account: String) throws { values.withLock { $0[account] = secret } }
    package func delete(account: String) throws { _ = values.withLock { $0.removeValue(forKey: account) } }
}
