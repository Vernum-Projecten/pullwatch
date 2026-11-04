import Foundation
import PullwatchCore
import Synchronization
import Testing
@testable import PullwatchGitHub
import PullwatchTestSupport

/// Verversen van GitHub App-tokens: één refresh per account, en een afgebroken vrager verliest het
/// nieuwe paar niet.
@Suite struct GitHubAppTokenRefresherTests {
    let config = GitHubAppConfig(clientID: "Iv23test", slug: "pullwatch-dev")
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let old: GitHubAppTokens
    let fresh = #"{"access_token":"fresh","expires_in":28800,"refresh_token":"r2","refresh_token_expires_in":15897600}"#

    init() {
        old = GitHubAppTokens(access: "old", accessExpires: start, refresh: "r1")
    }

    func source(_ http: any HTTPClient, store: GitHubAppTokenStore, refresher: GitHubAppTokenRefresher) -> GitHubAppTokenSource {
        let fixed = start
        let flow = GitHubDeviceFlow(config: config, http: http, now: { fixed }, second: .milliseconds(1))
        return GitHubAppTokenSource(flow: flow, store: store, now: { fixed }, refresher: refresher)
    }

    @Test func `A cancelled caller still ends with the new tokens stored`() async throws {
        let mock = MockHTTPClient()
        mock.on("login/oauth/access_token", body: fresh)
        let http = GatedHTTPClient(mock)
        let store = GitHubAppTokenStore(accountId: UUID(), secrets: InMemorySecretStore())
        try store.save(old)
        let tokens = source(http, store: store, refresher: GitHubAppTokenRefresher())

        let caller = Task { try await tokens.token() }
        await http.arrivals.reached(1)
        caller.cancel()
        http.open()
        _ = try? await caller.value

        #expect(store.load()?.access == "fresh")
        #expect(store.load()?.refresh == "r2")
    }

    @Test func `Two callers at once cause one refresh request`() async throws {
        let mock = MockHTTPClient()
        mock.on("login/oauth/access_token", body: fresh)
        let http = GatedHTTPClient(mock)
        let secrets = CountingSecretStore()
        let store = GitHubAppTokenStore(accountId: UUID(), secrets: secrets)
        try store.save(old)
        let refresher = GitHubAppTokenRefresher()
        // Twee token sources voor hetzelfde account, zoals een poll en een versiecontrole die elk
        // hun eigen provider maken.
        let first = source(http, store: store, refresher: refresher)
        let second = source(http, store: store, refresher: refresher)

        let one = Task { try await first.token() }
        await http.arrivals.reached(1)
        let two = Task { try await second.token() }
        // De tweede heeft de oude tokens gelezen en wacht nu op de refresh die al loopt.
        await secrets.reads.reached(2)
        http.open()

        #expect(try await one.value == "fresh")
        #expect(try await two.value == "fresh")
        #expect(mock.requests.count == 1)
        #expect(store.load()?.refresh == "r2")
    }

    @Test func `A failed refresh keeps the old tokens`() async throws {
        let http = MockHTTPClient()
        http.on("login/oauth/access_token", body: #"{"error":"bad_refresh_token"}"#)
        let store = GitHubAppTokenStore(accountId: UUID(), secrets: InMemorySecretStore())
        try store.save(old)
        let tokens = source(http, store: store, refresher: GitHubAppTokenRefresher())

        await #expect(throws: ProviderError.unauthorized) { try await tokens.token() }
        #expect(store.load() == old)
    }

    @Test func `A refresh that hits a network error keeps the old tokens`() async throws {
        let http = MockHTTPClient()
        let store = GitHubAppTokenStore(accountId: UUID(), secrets: InMemorySecretStore())
        try store.save(old)
        let tokens = source(http, store: store, refresher: GitHubAppTokenRefresher())

        await #expect(throws: ProviderError.self) { try await tokens.token() }
        #expect(store.load() == old)
    }
}

// MARK: - Hulpjes

/// Een teller waarop een test wacht tot hij een stand haalt, zonder te slapen.
final class Tally: Sendable {
    private struct State {
        var count = 0
        var waiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }

    private let state = Mutex(State())

    func increment() {
        let ready = state.withLock { state in
            state.count += 1
            let count = state.count
            let ready = state.waiters.filter { $0.target <= count }
            state.waiters.removeAll { $0.target <= count }
            return ready
        }
        for waiter in ready { waiter.continuation.resume() }
    }

    func reached(_ target: Int) async {
        await withCheckedContinuation { continuation in
            let now = state.withLock { state in
                if state.count >= target { return true }
                state.waiters.append((target, continuation))
                return false
            }
            if now { continuation.resume() }
        }
    }
}

/// Houdt elk verzoek vast tot de test `open()` roept, en gooit daarna zoals URLSession als de taak
/// van het verzoek intussen is afgebroken.
final class GatedHTTPClient: HTTPClient {
    let inner: MockHTTPClient
    let arrivals = Tally()
    private let opened = Tally()

    init(_ inner: MockHTTPClient) {
        self.inner = inner
    }

    func open() { opened.increment() }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        arrivals.increment()
        await opened.reached(1)
        try Task.checkCancellation()
        return try await inner.send(request)
    }
}

/// Een `InMemorySecretStore` die telt hoe vaak er gelezen is.
final class CountingSecretStore: SecretStore {
    private let inner = InMemorySecretStore()
    let reads = Tally()

    func read(account: String) throws -> String? {
        defer { reads.increment() }
        return try inner.read(account: account)
    }

    func write(_ secret: String, account: String) throws { try inner.write(secret, account: account) }
    func delete(account: String) throws { try inner.delete(account: account) }
}
