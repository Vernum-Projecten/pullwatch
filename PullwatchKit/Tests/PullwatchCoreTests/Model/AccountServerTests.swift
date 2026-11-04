import Foundation
import Testing
@testable import PullwatchCore

/// Een account op een eigen server zonder bruikbaar adres is niet af (#217): Forgejo zonder
/// server, een http-adres of ander onzin-adres in config.json. Zo'n account wordt niet gepold,
/// zegt wat er ontbreekt en blijft zo bewaard.
@Suite struct AccountServerTests {
    /// Een account zoals het in config.json staat, met `instanceURL` als tekst.
    func decode(kind: String, instanceURL: String?, flavour: String? = nil) throws -> Account {
        var fields = [
            #""id":"6F9619FF-8B86-D011-B42D-00C04FC964FF""#, #""kind":"\#(kind)""#, #""owners":["acme"]"#,
            #""organization":"acme""#, #""authMethod":"pat""#, #""repoWatch":{}"#, #""newRepoDefault":"prs""#,
            #""includeDrafts":false"#, #""hideOwn":true"#,
        ]
        if let instanceURL { fields.append(#""instanceURL":"\#(instanceURL)""#) }
        if let flavour { fields.append(#""giteaFlavour":"\#(flavour)""#) }
        return try JSONDecoder().decode(Account.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    @Test func `Forgejo without a server is incomplete and says the server is missing`() {
        let account = Account(kind: .gitea, organization: "acme", authMethod: .pat, giteaFlavour: .forgejo)
        #expect(account.hasOwner)
        #expect(account.serverProblem == .missing)
        #expect(!account.isComplete)
        #expect(account.serverProblemMessage?.contains("Forgejo") == true)
        #expect(AppConfig(accounts: [account]).pollableAccounts.isEmpty)
    }

    @Test(arguments: [
        (GiteaFlavour.codeberg, nil as String?),
        (.gitea, nil),
        (.forgejo, "https://forgejo.example.com"),
        (.gitea, "https://git.example.com"),
    ])
    func `A flavour with its server is complete`(flavour: GiteaFlavour, server: String?) {
        let account = Account(kind: .gitea, organization: "acme", authMethod: .pat, instanceURL: server.flatMap(URL.init(string:)), giteaFlavour: flavour)
        #expect(account.serverProblem == nil)
        #expect(account.isComplete)
    }

    @Test(arguments: ["gitHub", "gitLab", "gitea"])
    func `An http server in config.json decodes to an incomplete account`(kind: String) throws {
        let account = try decode(kind: kind, instanceURL: "http://git.example.com", flavour: kind == "gitea" ? "forgejo" : nil)
        #expect(account.instanceURL == nil, "nooit terugvallen op github.com, gitlab.com of codeberg.org")
        #expect(account.serverProblem == .invalid("http://git.example.com"))
        #expect(!account.isComplete)
        #expect(account.serverProblemMessage?.contains("http://git.example.com") == true)
        #expect(AppConfig(accounts: [account]).pollableAccounts.isEmpty)
    }

    @Test(arguments: ["https://user:pw@git.example.com", "https://git.example.com?x=1", "git", "ftp://git.example.com"])
    func `Other unusable servers in config.json are incomplete too`(text: String) throws {
        let account = try decode(kind: "gitLab", instanceURL: text)
        #expect(account.instanceURL == nil)
        #expect(account.serverProblem == .invalid(text))
    }

    @Test func `An unusable server is written back as it was`() throws {
        let account = try decode(kind: "gitHub", instanceURL: "http://github.example.com")
        let again = try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(account))
        #expect(again == account)
        #expect(again.serverProblem == .invalid("http://github.example.com"))
    }

    @Test(arguments: [
        ("gitHub", "https://github.example.com", "https://github.example.com"),
        ("gitLab", "https://GIT.example.com/", "https://git.example.com"),
        ("gitea", "https://git.example.com/api/v1", "https://git.example.com"),
    ])
    func `A https server in config.json goes through InstanceURL.parse`(kind: String, text: String, expected: String) throws {
        let account = try decode(kind: kind, instanceURL: text, flavour: kind == "gitea" ? "forgejo" : nil)
        #expect(account.instanceURL?.absoluteString == expected)
        #expect(account.serverProblem == nil)
        #expect(account.isComplete)
    }

    @Test func `Without a server field the service's own server is used`() throws {
        let account = try decode(kind: "gitHub", instanceURL: nil)
        #expect(account.instanceURL == nil)
        #expect(account.serverProblem == nil)
        #expect(account.effectiveInstanceURL?.absoluteString == "https://github.com")
    }

    @Test func `An own server left empty is missing, not the service's own server`() {
        var account = Account(kind: .gitHub, organization: "acme", authMethod: .pat)
        account.unusableInstanceURL = ""
        #expect(account.serverProblem == .missing)
        #expect(!account.isComplete)
    }

    @Test func `An http URL set in code is no server either`() {
        let account = Account(kind: .gitLab, organization: "acme", authMethod: .pat, instanceURL: URL(string: "http://git.example.com"))
        #expect(account.serverProblem == .invalid("http://git.example.com"))
    }

    @Test(arguments: [ProviderKind.azureDevOps, .bitbucket])
    func `Services without an own server never have a server problem`(kind: ProviderKind) {
        #expect(Account(kind: kind, organization: "acme", authMethod: .pat).serverProblem == nil)
    }

    @Test(arguments: [
        ("nl", "Het adres van de Forgejo-server ontbreekt"),
        ("en", "The address of the Forgejo server is missing"),
        ("de", "Die Adresse des Forgejo-Servers fehlt"),
        ("fr", "L’adresse du serveur Forgejo est manquante"),
    ])
    func `A missing server names the service in every language`(language: String, expected: String) {
        #expect(ProviderError.unusableServer(service: "Forgejo", problem: .missing).userMessage(bundle: .core(for: language)) == expected)
    }

    @Test(arguments: [
        ("nl", "Het serveradres http://x.example.com is geen geldig https-adres"),
        ("en", "The server address http://x.example.com is not a valid https address"),
        ("de", "Die Serveradresse http://x.example.com ist keine gültige https-Adresse"),
        ("fr", "L’adresse du serveur http://x.example.com n’est pas une adresse https valide"),
    ])
    func `An unusable server names the address in every language`(language: String, expected: String) {
        let problem = Account.ServerProblem.invalid("http://x.example.com")
        #expect(ProviderError.unusableServer(service: "Forgejo", problem: problem).userMessage(bundle: .core(for: language)) == expected)
    }
}
