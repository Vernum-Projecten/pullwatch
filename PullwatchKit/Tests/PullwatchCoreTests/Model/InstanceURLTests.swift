import Foundation
import Testing
@testable import PullwatchCore

@Suite struct InstanceURLTests {
    @Test(arguments: [
        ("gitlab.example.com", "https://gitlab.example.com"),
        ("https://GitLab.Example.com/", "https://gitlab.example.com"),
        ("  https://git.example.com/gitlab//  ", "https://git.example.com/gitlab"),
        ("https://git.example.com:8443", "https://git.example.com:8443"),
        ("https://gitlab.example.com/api/v4", "https://gitlab.example.com"),
    ])
    func acceptsHTTPSAddresses(text: String, expected: String) {
        #expect(InstanceURL.parse(text)?.absoluteString == expected)
    }

    @Test(arguments: [
        "", "http://gitlab.example.com", "ftp://gitlab.example.com", "https://", "gitlab",
        "https://user:pass@gitlab.example.com", "https://gitlab.example.com?x=1",
        "https://gitlab.example.com/#top", "gitlab example.com",
    ])
    func refusesEverythingElse(text: String) {
        #expect(InstanceURL.parse(text) == nil)
    }

    @Test func gitLabAccountsUseTheirServer() throws {
        var account = Account(kind: .gitLab, organization: "acme/platform", authMethod: .pat)
        #expect(account.effectiveInstanceURL?.absoluteString == "https://gitlab.com")
        #expect(account.serviceName == "GitLab")
        #expect(account.repoWebURL("acme/platform/api")?.absoluteString == "https://gitlab.com/acme/platform/api")
        #expect(account.avatarURL == nil)

        account.instanceURL = InstanceURL.parse("git.example.com/gitlab")
        #expect(account.serviceName == "git.example.com")
        #expect(account.repoWebURL("team/app")?.absoluteString == "https://git.example.com/gitlab/team/app")

        // Een eigen server geldt alleen voor diensten die er een kennen.
        var azure = Account(kind: .azureDevOps, organization: "contoso", authMethod: .pat)
        azure.instanceURL = URL(string: "https://example.com")
        #expect(azure.effectiveInstanceURL == nil)
        #expect(azure.serviceName == "Azure DevOps")
    }

    @Test(arguments: [
        ("github.example.com", "https://github.example.com"),
        ("https://github.example.com/api/v3", "https://github.example.com"),
        ("https://github.example.com/api/v3/", "https://github.example.com"),
        ("https://github.example.com/api/graphql", "https://github.example.com"),
        ("acme.ghe.com", "https://acme.ghe.com"),
        ("https://api.acme.ghe.com", "https://acme.ghe.com"),
        ("api.github.com", "https://github.com"),
        ("https://GitHub.com/", "https://github.com"),
    ])
    func gitHubAddressesBecomeTheWebAddress(text: String, expected: String) {
        #expect(InstanceURL.parse(text, for: .gitHub)?.absoluteString == expected)
    }

    @Test func gitLabKeepsApiPathsThatAreNotItsOwn() {
        #expect(InstanceURL.parse("https://git.example.com/api/v3", for: .gitLab)?.absoluteString == "https://git.example.com/api/v3")
        #expect(InstanceURL.parse("http://github.example.com", for: .gitHub) == nil)
    }

    @Test(arguments: [
        "acme/web",
        "https://github.example.com/acme/web",
        "https://GitHub.Example.com/acme/web/pull/4",
        "github.example.com/acme/web.git",
        "git@github.example.com:acme/web.git",
    ])
    func linksToTheEnterpriseServerAreGitHubRepos(_ input: String) throws {
        let repo = try RepositoryReference.parse(
            input, kind: .gitHub, organization: "acme", instanceURL: URL(string: "https://github.example.com")
        )
        #expect(repo == "acme/web")
    }

    @Test func aLinkToAnotherServerIsNotARepoOfTheEnterpriseAccount() {
        #expect(throws: RepositoryProblem.self) {
            try RepositoryReference.parse(
                "https://git.other.com/acme/web", kind: .gitHub, organization: "acme",
                instanceURL: URL(string: "https://github.example.com")
            )
        }
    }

    @Test func gitHubAccountsOnAnEnterpriseServer() {
        var account = Account(kind: .gitHub, organization: "octo", authMethod: .pat)
        #expect(!account.isGitHubEnterprise)
        #expect(account.serviceName == "GitHub")
        #expect(account.repoWebURL("octo/app")?.absoluteString == "https://github.com/octo/app")
        #expect(account.avatarURL?.absoluteString == "https://github.com/octo.png?size=128")

        account.instanceURL = URL(string: "https://github.example.com")
        #expect(account.isGitHubEnterprise)
        #expect(account.serviceName == "github.example.com")
        #expect(account.displayName.contains("github.example.com"))
        #expect(account.repoWebURL("octo/app")?.absoluteString == "https://github.example.com/octo/app")
        #expect(account.avatarURL?.absoluteString == "https://github.example.com/octo.png?size=128")

        account.instanceURL = URL(string: "https://acme.ghe.com")
        #expect(account.serviceName == "acme.ghe.com")
        #expect(account.repoWebURL("octo/app")?.absoluteString == "https://acme.ghe.com/octo/app")

        account.instanceURL = URL(string: "https://github.com")
        #expect(!account.isGitHubEnterprise, "github.com is geen eigen server")
    }

    @Test func gitLabAccountRoundTripsAndOldConfigStillDecodes() throws {
        let account = Account(
            kind: .gitLab, organization: "acme", authMethod: .cli,
            instanceURL: URL(string: "https://git.example.com")
        )
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        #expect(decoded == account)
        #expect(decoded.kind == .gitLab)
        #expect(String(decoding: data, as: UTF8.self).contains(#""kind":"gitLab""#))

        // Van vóór GitLab: geen `instanceURL`, en de bestaande diensten houden hun rawValue.
        let old = #"{"id":"00000000-0000-0000-0000-000000000009","kind":"gitHub","organization":"octo","authMethod":"pat","includeDrafts":false,"hideOwn":true}"#
        let legacy = try JSONDecoder().decode(Account.self, from: Data(old.utf8))
        #expect(legacy.instanceURL == nil)
        #expect(legacy.kind == .gitHub)
        #expect(!String(decoding: try JSONEncoder().encode(legacy), as: UTF8.self).contains("instanceURL"))
        #expect(ProviderKind.allCases.map(\.rawValue) == ["azureDevOps", "gitHub", "gitLab", "bitbucket", "gitea"])
    }
}
