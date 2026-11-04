import CryptoKit
public import Foundation
import Synchronization

/// Waar deze run zijn tokens bewaart. De echte app: de login-Keychain onder
/// `nl.torrisi.pullwatch`. Met een eigen datamap (`-PullwatchDataDirectory`) een eigen
/// Keychain-service per map, zodat een proefrun nooit de tokens van de echte app ziet of
/// opruimt. Met `-PullwatchEphemeralSecrets` of het nagespeelde GitHub (`-PullwatchFakeGitHub`)
/// alleen in het geheugen: UI-tests en schermafbeeldingen laten zo niets achter.
public enum SecretStores {
    static let ephemeralKey = "PullwatchEphemeralSecrets"
    static let fakeGitHubKey = "PullwatchFakeGitHub"
    static let defaultService = "nl.torrisi.pullwatch"

    /// De opslag van deze run, één keer bepaald uit de launch-argumenten.
    public static let shared: any SecretStore = make(defaults: .standard)

    static func make(defaults: UserDefaults) -> any SecretStore {
        if defaults.bool(forKey: ephemeralKey) || defaults.bool(forKey: fakeGitHubKey) {
            return EphemeralSecretStore()
        }
        return KeychainStore(service: service(defaults: defaults))
    }

    /// `nl.torrisi.pullwatch`, of met een eigen datamap `nl.torrisi.pullwatch.dev.<hash van de map>`.
    static func service(defaults: UserDefaults) -> String {
        guard let override = defaults.string(forKey: AppPaths.directoryOverrideKey), !override.isEmpty else {
            return defaultService
        }
        let path = URL(filePath: override, directoryHint: .isDirectory).standardizedFileURL.path(percentEncoded: false)
        let digest = SHA256.hash(data: Data(path.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return "\(defaultService).dev.\(digest)"
    }

    /// De Keychain-items van Pullwatch die bij geen account meer horen: `<uuid>` (PAT) en
    /// `github-app.<uuid>` (Inloggen met GitHub). Andere namen blijven altijd staan.
    public static func orphans(in names: [String], keeping accountIds: Set<UUID>) -> [String] {
        names.filter { name in
            let id = name.hasPrefix("github-app.") ? String(name.dropFirst("github-app.".count)) : name
            guard let uuid = UUID(uuidString: id) else { return false }
            return !accountIds.contains(uuid)
        }
    }

    /// Ruimt bij het starten tokens op van accounts die niet meer in de config staan (een
    /// afgebroken toevoegen, een crash, een oudere versie). Geeft terug hoeveel er weg zijn.
    @discardableResult
    public static func removeOrphans(keeping accountIds: Set<UUID>, store: any SecretStore = shared) -> Int {
        guard let keychain = store as? KeychainStore, let names = try? keychain.accounts() else { return 0 }
        let orphans = orphans(in: names, keeping: accountIds)
        for name in orphans { try? keychain.delete(account: name) }
        return orphans.count
    }
}

/// Tokens alleen in het geheugen van deze run.
final class EphemeralSecretStore: SecretStore {
    private let secrets = Mutex<[String: String]>([:])

    public init() {}

    public func read(account: String) throws -> String? {
        secrets.withLock { $0[account] }
    }

    public func write(_ secret: String, account: String) throws {
        secrets.withLock { $0[account] = secret }
    }

    public func delete(account: String) throws {
        _ = secrets.withLock { $0.removeValue(forKey: account) }
    }
}
