import Foundation
import Testing
import PullwatchAzureDevOps
import PullwatchBitbucket
import PullwatchCore
import PullwatchGitHub
import PullwatchGitLab
import PullwatchProviders
import PullwatchTestSupport

@Suite struct ProviderFactoryTests {
    @Test func factoryPicksProviderByKind() {
        #expect(ProviderFactory.make(Account.fixture(kind: .azureDevOps)) is AzureDevOpsProvider)
        #expect(ProviderFactory.make(Account.fixture(kind: .gitHub)) is GitHubProvider)
        #expect(ProviderFactory.make(Account.fixture(kind: .gitLab)) is GitLabProvider)
        #expect(ProviderFactory.make(Account.fixture(kind: .bitbucket)) is BitbucketProvider)
    }

    @Test func `Bitbucket signs in with the account email and the token from the Keychain`() async throws {
        let http = MockHTTPClient()
        http.on("https://api.bitbucket.org/2.0/user", body: #"{"uuid":"{1}","display_name":"Jane"}"#)
        var account = Account.fixture(kind: .bitbucket)
        account.email = "jane@example.com"
        let secrets = InMemorySecretStore()
        try secrets.write("ATATT-stored", account: account.id.uuidString)
        #expect(try await ProviderFactory.make(account, secrets: secrets, http: http).currentUserId() == "{1}")
        let expected = "Basic " + Data("jane@example.com:ATATT-stored".utf8).base64EncodedString()
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == expected)
    }

    @Test func `Bitbucket uses a typed token before the Keychain`() async throws {
        let http = MockHTTPClient()
        http.on("https://api.bitbucket.org/2.0/user", body: #"{"uuid":"{1}","display_name":"Jane"}"#)
        var account = Account.fixture(kind: .bitbucket)
        account.email = "jane@example.com"
        _ = try await ProviderFactory.make(account, pat: "ATATT-typed", secrets: InMemorySecretStore(), http: http).currentUserId()
        let expected = "Basic " + Data("jane@example.com:ATATT-typed".utf8).base64EncodedString()
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == expected)
    }

    @Test func gitLabTalksToItsOwnServer() async throws {
        let http = MockHTTPClient()
        http.on("https://git.example.com/api/v4/user", body: #"{"id":1,"username":"me"}"#)
        var account = Account.fixture(kind: .gitLab)
        account.instanceURL = URL(string: "https://git.example.com")
        let provider = ProviderFactory.make(account, pat: "glpat-typed", secrets: InMemorySecretStore(), http: http)
        #expect(try await provider.currentUserId() == "me")
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer glpat-typed")
    }

    @Test func gitHubEnterpriseTalksToItsOwnServer() async throws {
        let http = MockHTTPClient()
        http.on("https://github.example.com/api/v3/user", body: #"{"login":"me"}"#)
        var account = Account.fixture(kind: .gitHub)
        account.instanceURL = URL(string: "https://github.example.com")
        let provider = ProviderFactory.make(account, pat: "ghp_typed", secrets: InMemorySecretStore(), http: http)
        #expect(try await provider.currentUserId() == "me")
        #expect(http.requests.map(\.url?.absoluteString) == ["https://github.example.com/api/v3/user"])
    }

    @Test func factoryUsesPatOverrideBeforeKeychain() async throws {
        let http = MockHTTPClient()
        http.on("github.com/user", body: #"{"login":"me"}"#)
        let provider = ProviderFactory.make(Account.fixture(kind: .gitHub), pat: "typed", secrets: InMemorySecretStore(), http: http)
        _ = try await provider.currentUserId()
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer typed")
    }

    @Test func factoryReadsPatFromSecretStore() async throws {
        let http = MockHTTPClient()
        http.on("github.com/user", body: #"{"login":"me"}"#)
        let account = Account.fixture(kind: .gitHub)
        let secrets = InMemorySecretStore()
        try secrets.write("stored", account: account.id.uuidString)
        _ = try await ProviderFactory.make(account, secrets: secrets, http: http).currentUserId()
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer stored")
    }

    @Test func factoryUsesTheGitHubAppTokensForThatAuthMethod() async throws {
        let config = GitHubAppConfig(clientID: "Iv23test", slug: "pullwatch-dev")
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
