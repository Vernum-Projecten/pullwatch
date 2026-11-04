import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Packages lezen met de GitHub CLI (`Account.packagesViaCLI`, #206): standaard aan, per account
/// bewaard, en een oude config zonder het veld krijgt de standaard.
@Suite struct PackagesViaCLITests {
    @Test func `A new account reads packages with the CLI by default`() {
        let account = Account(kind: .gitHub, organization: "acme", authMethod: .gitHubApp)
        #expect(account.packagesViaCLI == nil)
        #expect(account.readsPackagesWithCLI)
    }

    @Test func `A config from before the setting decodes to the default`() throws {
        let json = #"""
        {"id":"7D3C1A46-2F42-4D7A-9A0B-2C3D4E5F6A7B","kind":"gitHub","organization":"acme","owners":["acme"],
         "authMethod":"gitHubApp","repoWatch":{},"newRepoDefault":"none","includeDrafts":false,"hideOwn":true}
        """#
        let account = try JSONDecoder().decode(Account.self, from: Data(json.utf8))
        #expect(account.packagesViaCLI == nil)
        #expect(account.readsPackagesWithCLI)
    }

    @Test(arguments: [true, false])
    func `A chosen setting survives the config`(isOn: Bool) throws {
        var account = Account(kind: .gitHub, organization: "acme", authMethod: .gitHubApp)
        account.packagesViaCLI = isOn
        let decoded = try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(account))
        #expect(decoded.packagesViaCLI == isOn)
        #expect(decoded.readsPackagesWithCLI == isOn)
        #expect(decoded == account)
    }

    @Test func `The default is not written`() throws {
        let account = Account(kind: .gitHub, organization: "acme", authMethod: .gitHubApp)
        let encoded = String(decoding: try JSONEncoder().encode(account), as: UTF8.self)
        #expect(!encoded.contains("packagesViaCLI"))
    }
}
