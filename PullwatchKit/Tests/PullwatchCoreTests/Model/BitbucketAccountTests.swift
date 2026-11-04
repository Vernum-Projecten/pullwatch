import Foundation
import Testing
@testable import PullwatchCore

/// Een Bitbucket-account: het e-mailadres in de config, de repo's in de vorm `workspace/repo`, en
/// de hosts in het overzicht van bronnen.
@Suite struct BitbucketAccountTests {
    func parse(_ input: String, _ kind: ProviderKind = .bitbucket) -> Result<String, RepositoryProblem> {
        Result { () throws(RepositoryProblem) -> String in
            try RepositoryReference.parse(input, kind: kind, organization: "atlassian")
        }
    }

    @Test func `The email is kept in the config`() throws {
        let account = Account(kind: .bitbucket, organization: "atlassian", authMethod: .pat, email: "jane@example.com")
        let data = try JSONEncoder().encode(account)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""email":"jane@example.com""#))
        #expect(text.contains(#""kind":"bitbucket""#))
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        #expect(decoded == account)
        #expect(decoded.displayName.hasPrefix("atlassian") && decoded.displayName.hasSuffix("Bitbucket"))
    }

    @Test func `An account from before has no email`() throws {
        let old = #"{"id":"00000000-0000-0000-0000-000000000009","kind":"gitHub","organization":"octo","authMethod":"pat","includeDrafts":false,"hideOwn":true}"#
        let account = try JSONDecoder().decode(Account.self, from: Data(old.utf8))
        #expect(account.email == nil)
        #expect(!String(decoding: try JSONEncoder().encode(account), as: UTF8.self).contains("email"))
    }

    @Test func `A repository links to bitbucket.org`() {
        let account = Account(kind: .bitbucket, organization: "atlassian", authMethod: .pat)
        #expect(account.repoWebURL("atlassian/aui")?.absoluteString == "https://bitbucket.org/atlassian/aui")
        #expect(account.serviceName == "Bitbucket")
    }

    @Test(arguments: [
        "atlassian/aui",
        "https://bitbucket.org/atlassian/aui",
        "https://bitbucket.org/atlassian/aui/pull-requests/5486",
        "https://bitbucket.org/atlassian/aui.git",
        "bitbucket.org/atlassian/aui/src/master/",
        "git@bitbucket.org:atlassian/aui.git",
    ])
    func `Reads a Bitbucket repository`(input: String) {
        #expect(parse(input) == .success("atlassian/aui"))
    }

    @Test(arguments: ["atlassian", "a/b/c", "atlassian/.hidden", "https://bitbucket.org/atlassian"])
    func `Refuses what is no Bitbucket repository`(input: String) {
        #expect(parse(input) == .failure(.unrecognised(.bitbucket)))
    }

    @Test func `A Bitbucket link at another account says so`() {
        #expect(parse("https://bitbucket.org/atlassian/aui", .gitHub) == .failure(.otherService(.bitbucket)))
    }

    @Test func `The sources overview names the API and the picture hosts`() {
        let account = Account(kind: .bitbucket, organization: "atlassian", authMethod: .pat, email: "jane@example.com")
        #expect(SourcesOverview.server(of: account).absoluteString == "https://api.bitbucket.org/2.0")
        #expect(SourcesOverview.pictureHosts(of: account).compactMap { $0.host() }
            == ["secure.gravatar.com", "avatar-management--avatars.us-west-2.prod.public.atl-paas.net"])
        #expect(VersionChecker.securitySource(for: .bitbucket) == nil)
    }
}
