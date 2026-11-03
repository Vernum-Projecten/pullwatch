import Foundation
import Testing
@testable import PullwatchCore

@Suite struct SecretStoresTests {
    private func defaults(_ values: [String: Any]) -> UserDefaults {
        let name = "SecretStoresTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        for (key, value) in values { defaults.set(value, forKey: key) }
        return defaults
    }

    @Test func realRunUsesTheAppService() {
        #expect(SecretStores.service(defaults: defaults([:])) == "nl.torrisi.pullwatch")
        #expect(SecretStores.make(defaults: defaults([:])) is KeychainStore)
    }

    @Test func ownDataDirectoryGetsItsOwnStableService() {
        let a = SecretStores.service(defaults: defaults([AppPaths.directoryOverrideKey: "/tmp/pw-a"]))
        let aAgain = SecretStores.service(defaults: defaults([AppPaths.directoryOverrideKey: "/tmp/pw-a/"]))
        let b = SecretStores.service(defaults: defaults([AppPaths.directoryOverrideKey: "/tmp/pw-b"]))
        #expect(a.hasPrefix("nl.torrisi.pullwatch.dev."))
        #expect(a == aAgain)
        #expect(a != b)
    }

    @Test(arguments: [SecretStores.ephemeralKey, "PullwatchFakeGitHub"])
    func testRunsKeepTokensInMemory(_ key: String) throws {
        let store = SecretStores.make(defaults: defaults([key: true]))
        #expect(store is EphemeralSecretStore)
        try store.write("secret", account: "a")
        #expect(try store.read(account: "a") == "secret")
        try store.delete(account: "a")
        #expect(try store.read(account: "a") == nil)
    }

    @Test func orphansAreTokensOfAccountsThatAreGone() {
        let kept = UUID(), gone = UUID()
        let names = [
            kept.uuidString, "github-app.\(kept.uuidString)",
            gone.uuidString, "github-app.\(gone.uuidString)",
            "something-else", "github-app.not-a-uuid",
        ]
        #expect(SecretStores.orphans(in: names, keeping: [kept]) == [gone.uuidString, "github-app.\(gone.uuidString)"])
        #expect(SecretStores.orphans(in: names, keeping: [kept, gone]).isEmpty)
    }

    @Test func removeOrphansCleansOnlyItsOwnService() throws {
        let store = KeychainStore(service: "nl.torrisi.pullwatch.tests.orphans")
        let kept = UUID(), gone = UUID()
        defer {
            for name in [kept.uuidString, "github-app.\(gone.uuidString)", "other"] { try? store.delete(account: name) }
        }
        try store.write("a", account: kept.uuidString)
        try store.write("b", account: "github-app.\(gone.uuidString)")
        try store.write("c", account: "other")

        #expect(SecretStores.removeOrphans(keeping: [kept], store: store) == 1)
        #expect(Set(try store.accounts()) == [kept.uuidString, "other"])
    }
}
