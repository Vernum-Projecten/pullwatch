import Foundation
import Testing
import PullwatchAzureDevOps
import PullwatchBitbucket
import PullwatchCore
@testable import PullwatchGitHub
import PullwatchGitea
import PullwatchGitLab
import PullwatchProviders
import PullwatchTestSupport

@Suite struct ProviderFactoryTests {
    @Test func factoryPicksProviderByKind() {
        #expect(ProviderFactory.make(Account.fixture(kind: .azureDevOps)) is AzureDevOpsProvider)
        #expect(ProviderFactory.make(Account.fixture(kind: .gitHub)) is GitHubProvider)
        #expect(ProviderFactory.make(Account.fixture(kind: .gitLab)) is GitLabProvider)
        #expect(ProviderFactory.make(Account.fixture(kind: .bitbucket)) is BitbucketProvider)
        #expect(ProviderFactory.make(Account.fixture(kind: .gitea)) is GiteaProvider)
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

    @Test(arguments: [
        (GiteaFlavour.codeberg, nil, "https://codeberg.org/api/v1/user"),
        (.gitea, nil, "https://gitea.com/api/v1/user"),
        (.forgejo, "https://forgejo.example.com", "https://forgejo.example.com/api/v1/user"),
        (.gitea, "https://example.com/gitea", "https://example.com/gitea/api/v1/user"),
    ])
    func `Gitea talks to the server of its flavour with the typed token`(flavour: GiteaFlavour, server: String?, expected: String) async throws {
        let http = MockHTTPClient()
        http.on(expected, body: #"{"id":1,"login":"me","full_name":"Me"}"#)
        var account = Account.fixture(kind: .gitea)
        account.giteaFlavour = flavour
        account.instanceURL = server.flatMap(URL.init(string:))
        let provider = ProviderFactory.make(account, pat: "typed", secrets: InMemorySecretStore(), http: http)
        #expect(try await provider.currentUserId() == "me")
        #expect(http.requests.map(\.url?.absoluteString) == [expected])
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "token typed")
    }

    @Test func `Forgejo without a server sends no request and no token`() async throws {
        let http = MockHTTPClient()
        var account = Account.fixture(kind: .gitea)
        account.giteaFlavour = .forgejo
        let provider = ProviderFactory.make(account, pat: "typed", secrets: InMemorySecretStore(), http: http)
        await #expect(throws: ProviderError.unusableServer(service: "Forgejo", problem: .missing)) {
            try await provider.currentUserId()
        }
        await #expect(throws: ProviderError.unusableServer(service: "Forgejo", problem: .missing)) {
            try await provider.openPullRequests()
        }
        _ = try? await provider.listRepos()
        _ = try? await provider.publishedPackages(followedRepos: [])
        #expect(http.requests.isEmpty)
    }

    @Test(arguments: [ProviderKind.gitHub, .gitLab, .gitea])
    func `An http server from the config sends no request and no token`(kind: ProviderKind) async throws {
        let http = MockHTTPClient()
        http.on("example.com", body: "{}")
        http.on("github.com", body: "{}")
        http.on("gitlab.com", body: "{}")
        http.on("gitea.com", body: "{}")
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"\#(kind.rawValue)","owners":["acme"],"organization":"acme","authMethod":"pat","repoWatch":{},"newRepoDefault":"prs","includeDrafts":false,"hideOwn":true,"instanceURL":"http://git.example.com"}"#
        let account = try JSONDecoder().decode(Account.self, from: Data(json.utf8))
        let provider = ProviderFactory.make(account, pat: "typed", secrets: InMemorySecretStore(), http: http)
        await #expect(throws: ProviderError.unusableServer(service: account.productName, problem: .invalid("http://git.example.com"))) {
            try await provider.testConnection()
        }
        _ = try? await provider.pullRequests(updatedSince: nil, limit: 10)
        #expect(http.requests.isEmpty)
    }

    @Test func `Gitea reads its token from the Keychain`() async throws {
        let http = MockHTTPClient()
        http.on("https://codeberg.org/api/v1/user", body: #"{"id":1,"login":"me"}"#)
        var account = Account.fixture(kind: .gitea)
        account.giteaFlavour = .codeberg
        let secrets = InMemorySecretStore()
        try secrets.write("stored", account: account.id.uuidString)
        _ = try await ProviderFactory.make(account, secrets: secrets, http: http).currentUserId()
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "token stored")
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

    // MARK: - Packages van een GitHub App-account via gh (#206)

    /// Een GitHub App-account met een geldig app-token "ghu_from_app" in `secrets`.
    func appAccount(secrets: InMemorySecretStore, packagesViaCLI: Bool?) throws -> Account {
        var account = Account(kind: .gitHub, organization: "acme", authMethod: .gitHubApp)
        account.packagesViaCLI = packagesViaCLI
        try GitHubAppTokenStore(accountId: account.id, secrets: secrets)
            .save(GitHubAppTokens(access: "ghu_from_app", accessExpires: .distantFuture, refresh: "r"))
        return account
    }

    @Test(arguments: [nil, true])
    func `A GitHub App account reads packages with the gh token of its host`(packagesViaCLI: Bool?) async throws {
        let secrets = InMemorySecretStore()
        let http = MockHTTPClient()
        http.on("api.github.com/users/acme", body: #"{"login":"acme","type":"Organization"}"#)
        http.on("packages?package_type=", headers: ["X-OAuth-Scopes": "repo, read:packages"], body: "[]")
        let runner = MockProcessRunner()
        runner.output = ProcessOutput(status: 0, stdout: "gho_from_cli\n", stderr: "")
        let account = try appAccount(secrets: secrets, packagesViaCLI: packagesViaCLI)
        let provider = ProviderFactory.make(
            account, secrets: secrets, http: http, runner: runner, locator: .homebrew,
            gitHubApp: GitHubAppConfig(clientID: "Iv23test", slug: "pullwatch-dev")
        )

        #expect(try await provider.publishedPackages(followedRepos: ["acme/web"]) == .packages([]))

        let registry = http.requests.filter { $0.url?.path().contains("/packages") == true }
        #expect(!registry.isEmpty)
        #expect(registry.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer gho_from_cli" })
        #expect(runner.calls.map(\.1) == [["auth", "token"]])
    }

    @Test func `A GitHub App account with the setting off asks neither gh nor GitHub`() async throws {
        let secrets = InMemorySecretStore()
        let http = MockHTTPClient()
        let runner = MockProcessRunner()
        let provider = ProviderFactory.make(
            try appAccount(secrets: secrets, packagesViaCLI: false), secrets: secrets, http: http, runner: runner, locator: .homebrew,
            gitHubApp: GitHubAppConfig(clientID: "Iv23test", slug: "pullwatch-dev")
        )

        let result = try await provider.publishedPackages(followedRepos: ["acme/web"])

        #expect(result == .needsPermission(reason: GitHubPackagesReason.cliTurnedOff))
        #expect(http.requests.isEmpty)
        #expect(runner.calls.isEmpty)
    }

    @Test func `A token account keeps its own token for packages and never runs gh`() async throws {
        let secrets = InMemorySecretStore()
        let http = MockHTTPClient()
        http.on("api.github.com/users/acme", body: #"{"login":"acme","type":"Organization"}"#)
        http.on("packages?package_type=", body: "[]")
        let runner = MockProcessRunner()
        let provider = ProviderFactory.make(
            Account.fixture(kind: .gitHub), pat: "typed", secrets: secrets, http: http, runner: runner, locator: .homebrew
        )

        _ = try await provider.publishedPackages(followedRepos: ["acme/web"])

        #expect(http.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer typed" })
        #expect(runner.calls.isEmpty)
    }
}
