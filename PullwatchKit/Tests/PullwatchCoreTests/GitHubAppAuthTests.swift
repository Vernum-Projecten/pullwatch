import Foundation
import Testing
@testable import PullwatchCore

@Suite struct GitHubAppAuthTests {
    let config = GitHubAppConfig(clientID: "Iv23test", slug: "pullwatch-dev")
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func flow(_ http: MockHTTPClient, now: Date? = nil) -> GitHubDeviceFlow {
        let fixed = now ?? start
        return GitHubDeviceFlow(config: config, http: http, now: { fixed }, second: .milliseconds(1))
    }

    @Test func startsWithTheClientIdAndReturnsTheCode() async throws {
        let http = MockHTTPClient()
        http.on("login/device/code", body: #"{"device_code":"dc1","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#)
        let code = try await flow(http).start()
        #expect(code.userCode == "ABCD-1234")
        #expect(code.verificationURL.absoluteString == "https://github.com/login/device")
        #expect(code.expiresAt == start.addingTimeInterval(900))
        let request = try #require(http.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self) == "client_id=Iv23test")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func waitsWhilePendingThenReturnsTheTokens() async throws {
        let http = MockHTTPClient()
        http.onSequence("login/oauth/access_token", bodies: [
            #"{"error":"authorization_pending"}"#,
            #"{"error":"slow_down","interval":1}"#,
            #"{"access_token":"ghu_access","expires_in":28800,"refresh_token":"ghr_refresh","refresh_token_expires_in":15897600}"#,
        ])
        let code = DeviceCode(userCode: "X", verificationURL: URL(string: "https://github.com/login/device")!,
                              expiresAt: start.addingTimeInterval(900), deviceCode: "dc1", interval: 1)
        let tokens = try await flow(http).waitForTokens(code)
        #expect(tokens.access == "ghu_access")
        #expect(tokens.refresh == "ghr_refresh")
        #expect(tokens.accessExpires == start.addingTimeInterval(28800))
        #expect(http.requests.count == 3)
        let body = String(decoding: http.requests[0].httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("device_code=dc1"))
        #expect(body.contains("grant_type=urn:ietf:params:oauth:grant-type:device_code"))
    }

    @Test(arguments: [("access_denied", GitHubSignInError.denied), ("expired_token", .expired)])
    func stopsWhenGitHubSaysNo(_ answer: String, _ expected: GitHubSignInError) async {
        let http = MockHTTPClient()
        http.on("login/oauth/access_token", body: #"{"error":"\#(answer)"}"#)
        let code = DeviceCode(userCode: "X", verificationURL: URL(string: "https://github.com/login/device")!,
                              expiresAt: start.addingTimeInterval(900), deviceCode: "dc1", interval: 1)
        await #expect(throws: expected) { try await flow(http).waitForTokens(code) }
    }

    @Test func refusesWithoutAClientId() async {
        let http = MockHTTPClient()
        let unconfigured = GitHubDeviceFlow(config: GitHubAppConfig(clientID: "", slug: ""), http: http)
        await #expect(throws: GitHubSignInError.notConfigured) { try await unconfigured.start() }
        #expect(http.requests.isEmpty)
    }

    @Test func installLinkUsesTheSlug() {
        #expect(config.installURL.absoluteString == "https://github.com/apps/pullwatch-dev/installations/new")
    }

    @Test func storesTokensPerAccountInTheSecretStore() throws {
        let secrets = InMemorySecretStore()
        let id = UUID()
        let store = GitHubAppTokenStore(accountId: id, secrets: secrets)
        let tokens = GitHubAppTokens(access: "a", accessExpires: start, refresh: "r", refreshExpires: start.addingTimeInterval(60))
        try store.save(tokens)
        #expect(store.load() == tokens)
        #expect(try secrets.read(account: "github-app.\(id.uuidString)") != nil)
        #expect(GitHubAppTokenStore(accountId: UUID(), secrets: secrets).load() == nil)
        store.delete()
        #expect(store.load() == nil)
    }

    @Test func tokenSourceGivesTheStoredTokenWhileValid() async throws {
        let http = MockHTTPClient()
        let store = GitHubAppTokenStore(accountId: UUID(), secrets: InMemorySecretStore())
        try store.save(GitHubAppTokens(access: "still-good", accessExpires: start.addingTimeInterval(3600), refresh: "r"))
        let source = GitHubAppTokenSource(flow: flow(http), store: store, now: { [start] in start })
        #expect(try await source.token() == "still-good")
        #expect(http.requests.isEmpty)
    }

    @Test func tokenSourceRefreshesNearExpiryAndKeepsTheNewPair() async throws {
        let http = MockHTTPClient()
        http.on("login/oauth/access_token", body: #"{"access_token":"fresh","expires_in":28800,"refresh_token":"r2","refresh_token_expires_in":15897600}"#)
        let store = GitHubAppTokenStore(accountId: UUID(), secrets: InMemorySecretStore())
        try store.save(GitHubAppTokens(access: "old", accessExpires: start.addingTimeInterval(60), refresh: "r1"))
        let source = GitHubAppTokenSource(flow: flow(http), store: store, now: { [start] in start })
        #expect(try await source.token() == "fresh")
        #expect(store.load()?.refresh == "r2")
        let body = String(decoding: http.requests.first?.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("grant_type=refresh_token"))
        #expect(body.contains("refresh_token=r1"))
    }

    @Test func tokenSourceAsksToSignInAgainWhenTheRefreshFails() async throws {
        let http = MockHTTPClient()
        http.on("login/oauth/access_token", body: #"{"error":"bad_refresh_token"}"#)
        let store = GitHubAppTokenStore(accountId: UUID(), secrets: InMemorySecretStore())
        try store.save(GitHubAppTokens(access: "old", accessExpires: start, refresh: "dead"))
        let source = GitHubAppTokenSource(flow: flow(http), store: store, now: { [start] in start })
        await #expect(throws: ProviderError.unauthorized) { try await source.token() }
    }

    @Test func listsWhereTheAppIsInstalledOwnAccountFirst() async throws {
        let http = MockHTTPClient()
        http.on("user/installations", body: #"{"total_count":3,"installations":[{"account":{"login":"Vernum-Projecten"}},{"account":{"login":"octo"}},{"account":{"login":"acme"}}]}"#)
        http.on("api.github.com/user", body: #"{"login":"octo","id":1}"#)
        let provider = GitHubProvider(accountId: UUID(), owner: "", tokenSource: StaticTokenSource(token: "t"), http: http)
        #expect(try await provider.installationOwners() == ["octo", "acme", "Vernum-Projecten"])
        let url = try #require(http.requests.first?.url?.absoluteString)
        #expect(url.contains("per_page=100"))
    }

    @Test func factoryUsesTheGitHubAppTokensForThatAuthMethod() async throws {
        let secrets = InMemorySecretStore()
        let http = MockHTTPClient()
        http.on("api.github.com/user", body: #"{"login":"octo","id":1}"#)
        let account = Account(kind: .gitHub, organization: "octo", authMethod: .gitHubApp)
        try GitHubAppTokenStore(accountId: account.id, secrets: secrets)
            .save(GitHubAppTokens(access: "ghu_from_app", accessExpires: .distantFuture, refresh: "r"))
        let provider = ProviderFactory.make(account, secrets: secrets, http: http, gitHubApp: config)
        _ = try await provider.currentUserId()
        #expect(http.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer ghu_from_app")
    }
}
