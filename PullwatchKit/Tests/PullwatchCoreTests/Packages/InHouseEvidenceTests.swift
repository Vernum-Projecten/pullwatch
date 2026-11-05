import Foundation
import Testing
@testable import PullwatchCore

/// Welk register een install tot het eigen package van een account maakt (#214).
@Suite struct InHouseEvidenceTests {
    static let gitHub = Account(kind: .gitHub, organization: "acme", authMethod: .pat)
    static let enterprise = Account(kind: .gitHub, organization: "acme", authMethod: .pat, instanceURL: URL(string: "https://github.acme.example"))
    static let gitLab = Account(kind: .gitLab, organization: "acme", authMethod: .pat)
    static let azure = Account(kind: .azureDevOps, organization: "acme", authMethod: .pat)
    static let bitbucket = Account(kind: .bitbucket, organization: "acme", authMethod: .pat)

    struct Case: CustomTestStringConvertible, Sendable {
        let registry: String
        let ecosystem: String
        let account: Account
        let expected: Bool
        var testDescription: String { "\(account.kind) \(ecosystem) \(registry)" }
    }

    static let cases: [Case] = [
        // GitHub: een host per ecosysteem, de eigenaar vooraan in het pad.
        Case(registry: "https://npm.pkg.github.com/download/@acme/ui/2.1.0/8f3c", ecosystem: "npm", account: gitHub, expected: true),
        Case(registry: "https://npm.pkg.github.com/download/@other/ui/2.1.0/8f3c", ecosystem: "npm", account: gitHub, expected: false),
        Case(registry: "https://nuget.pkg.github.com/acme/index.json", ecosystem: "NuGet", account: gitHub, expected: true),
        Case(registry: "https://nuget.pkg.github.com/other/index.json", ecosystem: "NuGet", account: gitHub, expected: false),
        Case(registry: "https://rubygems.pkg.github.com/acme/", ecosystem: "RubyGems", account: gitHub, expected: true),
        Case(registry: "https://rubygems.pkg.github.com/acme/", ecosystem: "npm", account: gitHub, expected: false),
        Case(registry: "https://api.github.com/repos/acme/billing/zipball/0a1b", ecosystem: "Packagist", account: gitHub, expected: false),
        Case(registry: "http://npm.pkg.github.com/download/@acme/ui/2.1.0/8f3c", ecosystem: "npm", account: gitHub, expected: false),
        // GitHub Enterprise: subdomein of /_registry/.
        Case(registry: "https://npm.github.acme.example/@acme/ui/-/ui-2.1.0.tgz", ecosystem: "npm", account: enterprise, expected: true),
        Case(registry: "https://github.acme.example/_registry/nuget/acme/index.json", ecosystem: "NuGet", account: enterprise, expected: true),
        Case(registry: "https://npm.pkg.github.com/download/@acme/ui/2.1.0/8f3c", ecosystem: "npm", account: enterprise, expected: false),
        // GitLab: de API van de eigen host met het register van het ecosysteem.
        Case(registry: "https://gitlab.com/api/v4/projects/42/packages/npm/left-pad/-/left-pad-1.3.0.tgz", ecosystem: "npm", account: gitLab, expected: true),
        Case(registry: "https://gitlab.com/api/v4/projects/42/packages/pypi/simple", ecosystem: "PyPI", account: gitLab, expected: true),
        Case(registry: "https://gitlab.com/api/v4/group/7/-/packages/composer/packages.json", ecosystem: "Packagist", account: gitLab, expected: true),
        Case(registry: "https://gitlab.com/api/v4/projects/42/packages/nuget/index.json", ecosystem: "NuGet", account: gitLab, expected: true),
        Case(registry: "https://gitlab.com/api/v4/projects/42/packages/pypi/simple", ecosystem: "npm", account: gitLab, expected: false),
        Case(registry: "https://gitlab.com/api/v4/projects/42/repository/archive.zip", ecosystem: "Packagist", account: gitLab, expected: false),
        Case(registry: "https://gitlab.example.com/api/v4/projects/42/packages/pypi/simple", ecosystem: "PyPI", account: gitLab, expected: false),
        // Azure Artifacts: een feed van de organisatie.
        Case(registry: "https://pkgs.dev.azure.com/acme/_packaging/web/npm/registry/left-pad/-/left-pad-1.3.0.tgz", ecosystem: "npm", account: azure, expected: true),
        Case(registry: "https://pkgs.dev.azure.com/acme/Shop/_packaging/py/pypi/simple/", ecosystem: "PyPI", account: azure, expected: true),
        Case(registry: "https://acme.pkgs.visualstudio.com/_packaging/web/nuget/v3/index.json", ecosystem: "NuGet", account: azure, expected: true),
        Case(registry: "https://pkgs.dev.azure.com/other/_packaging/web/npm/registry/", ecosystem: "npm", account: azure, expected: false),
        Case(registry: "https://pkgs.dev.azure.com/acme/Shop/_git/web", ecosystem: "npm", account: azure, expected: false),
        // Een dienst zonder register dat Pullwatch leest.
        Case(registry: "https://bitbucket.org/acme/web", ecosystem: "npm", account: bitbucket, expected: false),
    ]

    @Test(arguments: cases)
    func `Only the account's own registry for the ecosystem is evidence`(_ item: Case) {
        #expect(InHouseEvidence.isOwnRegistry(item.registry, ecosystem: item.ecosystem, owner: "acme", account: item.account) == item.expected)
    }

    @Test(arguments: [
        ("@acme/ui", "acme", gitHub, true),
        ("@ACME/ui", "acme", gitHub, true),
        ("@other/ui", "acme", gitHub, false),
        ("ui", "acme", gitHub, false),
        ("@acme/ui", "acme/web", gitLab, true),
        ("@acme/ui", "Shop", azure, true),
        ("@shop/ui", "Shop", azure, true),
        ("@babel/core", "Shop", azure, false),
    ])
    func `A scoped npm name counts when the owner holds the scope`(name: String, owner: String, account: Account, expected: Bool) {
        #expect(InHouseEvidence.isOwnScope(name: name, owner: owner, account: account) == expected)
    }

    @Test func `A Go module path names its own source`() {
        let module = Dependency(ecosystem: "Go", name: "gitlab.com/acme/billing", version: "1.4.0", source: "go.mod")

        #expect(InHouseEvidence.proves(module, owner: "acme", account: Self.gitLab))
    }

    @Test func `A name alone is no evidence`() {
        let fork = Dependency(ecosystem: "NuGet", name: "Newtonsoft.Json", version: "13.0.1", source: "packages.lock.json")

        #expect(!InHouseEvidence.proves(fork, owner: "acme", account: Self.azure))
    }
}
