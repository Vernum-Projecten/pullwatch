import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Een account op Gitea, Forgejo of Codeberg: de smaak in de config, de naam en de server, en
/// wat je als losse repo intypt of plakt.
@Suite struct GiteaAccountTests {
    func parse(_ input: String, instance: String) -> Result<String, RepositoryProblem> {
        Result { () throws(RepositoryProblem) -> String in
            try RepositoryReference.parse(input, kind: .gitea, organization: "acme", instanceURL: URL(string: instance))
        }
    }

    @Test(arguments: [
        (GiteaFlavour.codeberg, nil, "Codeberg", "https://codeberg.org"),
        (.gitea, nil, "Gitea", "https://gitea.com"),
        (.forgejo, "https://git.example.com", "git.example.com", "https://git.example.com"),
        (.gitea, "https://gitea.com", "Gitea", "https://gitea.com"),
    ])
    func `The flavour gives the name and the server`(flavour: GiteaFlavour, server: String?, name: String, effective: String) {
        let account = Account(kind: .gitea, organization: "acme", authMethod: .pat, instanceURL: server.flatMap(URL.init(string:)), giteaFlavour: flavour)
        #expect(account.serviceName == name)
        #expect(account.effectiveInstanceURL?.absoluteString == effective)
        #expect(account.displayName.contains("acme"))
        #expect(account.repoWebURL("acme/api")?.absoluteString == "\(effective)/acme/api")
    }

    @Test(arguments: GiteaFlavour.allCases)
    func `The flavour survives the config`(flavour: GiteaFlavour) throws {
        let account = Account(kind: .gitea, organization: "acme", authMethod: .pat, giteaFlavour: flavour)
        let decoded = try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(account))
        #expect(decoded.giteaFlavour == flavour)
        #expect(decoded == account)
    }

    @Test func `Other services do not write a flavour`() throws {
        let account = Account(kind: .gitLab, organization: "acme", authMethod: .pat)
        let encoded = String(decoding: try JSONEncoder().encode(account), as: UTF8.self)
        #expect(!encoded.contains("giteaFlavour"))
    }

    @Test(arguments: [
        ("other/lib", "other/lib"),
        ("https://codeberg.org/other/lib", "other/lib"),
        ("https://codeberg.org/other/lib/pulls/12", "other/lib"),
        ("codeberg.org/other/lib.git", "other/lib"),
        ("git@codeberg.org:other/lib.git", "other/lib"),
        ("https://codeberg.org/other/my_lib.v2/src/branch/main", "other/my_lib.v2"),
    ])
    func `Reads a Codeberg repository typed or pasted`(input: String, repo: String) {
        #expect(parse(input, instance: "https://codeberg.org") == .success(repo))
    }

    @Test func `A link on an own server keeps the server's path`() {
        #expect(parse("https://example.com/forgejo/team/app/pulls", instance: "https://example.com/forgejo") == .success("team/app"))
    }

    @Test func `A link elsewhere says where it is`() {
        #expect(parse("https://gitea.com/gitea/tea", instance: "https://codeberg.org")
            == .failure(.otherServer(found: "gitea.com", expected: "codeberg.org")))
        #expect(parse("https://github.com/octo/app", instance: "https://codeberg.org") == .failure(.otherService(.gitHub)))
    }

    @Test(arguments: ["acme", "a/b/c", "owner/..", "owner/re po"])
    func `Rejects what is not owner and repo`(input: String) {
        #expect(parse(input, instance: "https://codeberg.org") == .failure(.unrecognised(.gitea)))
    }

    @Test(arguments: ["https://git.example.com/api/v1", "git.example.com/api/v1/", "https://git.example.com"])
    func `A pasted API address becomes the server`(text: String) {
        #expect(InstanceURL.parse(text, for: .gitea)?.absoluteString == "https://git.example.com")
    }

    @Test(arguments: ["http://git.example.com", "https://user:pw@git.example.com", "git"])
    func `Only https servers without credentials`(text: String) {
        #expect(InstanceURL.parse(text, for: .gitea) == nil)
    }

    @Test func `An untrusted certificate names the host`() throws {
        let request = URLRequest(url: try #require(URL(string: "https://git.example.com/api/v1/user")))
        for code in [URLError.Code.serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateHasBadDate] {
            #expect(URLSessionHTTPClient.providerError(for: URLError(code), request: request) == .untrustedCertificate("git.example.com"))
        }
    }

    @Test func `The sources overview lists the server and its pictures`() {
        let account = Account(kind: .gitea, organization: "acme", authMethod: .pat, giteaFlavour: .codeberg)
        #expect(SourcesOverview.server(of: account).absoluteString == "https://codeberg.org/api/v1")
        #expect(SourcesOverview.pictureHosts(of: account).map(\.absoluteString) == ["https://codeberg.org", "https://secure.gravatar.com"])
    }
}
