import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Welke dependency een eigen package is, per ecosysteem, en het lezen van oude en nieuwe rapporten.
@Suite struct InHousePackageTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let type: PublishedPackageType
        let published: String
        let owner: String
        let ecosystem: String
        let dependency: String
        let matches: Bool
        /// De dienst van het account; GitHub als niets gezegd.
        var kind: ProviderKind = .gitHub

        var testDescription: String { "\(kind.rawValue) \(type.rawValue) \(published) vs \(ecosystem) \(dependency): \(matches)" }
    }

    static let cases: [Case] = [
        // npm: de scope hoort bij de naam; GitHub noemt het package zonder scope.
        Case(type: .npm, published: "@acme/ui", owner: "acme", ecosystem: "npm", dependency: "@acme/ui", matches: true),
        Case(type: .npm, published: "ui", owner: "Acme", ecosystem: "npm", dependency: "@acme/ui", matches: true),
        Case(type: .npm, published: "ui", owner: "acme", ecosystem: "npm", dependency: "ui", matches: false),
        Case(type: .npm, published: "@acme/ui", owner: "acme", ecosystem: "npm", dependency: "@other/ui", matches: false),
        Case(type: .npm, published: "@acme/ui", owner: "acme", ecosystem: "npm", dependency: "@acme/UI", matches: false),
        // Azure Artifacts laat upstream-packages al weg: daar telt een naam zonder scope precies.
        Case(type: .npm, published: "acme-ui", owner: "Platform", ecosystem: "npm", dependency: "acme-ui", matches: true, kind: .azureDevOps),
        Case(type: .npm, published: "acme-ui", owner: "Platform", ecosystem: "npm", dependency: "@platform/acme-ui", matches: false, kind: .azureDevOps),
        Case(type: .npm, published: "@acme/ui", owner: "acme/web", ecosystem: "npm", dependency: "@acme/ui", matches: true, kind: .gitLab),
        // Packagist, crates.io en Go uit GitLab en Azure.
        Case(type: .composer, published: "Acme/Core", owner: "acme", ecosystem: "Packagist", dependency: "acme/core", matches: true, kind: .gitLab),
        Case(type: .cargo, published: "acme_core", owner: "Platform", ecosystem: "crates.io", dependency: "acme-core", matches: true, kind: .azureDevOps),
        Case(type: .golang, published: "gitlab.com/acme/lib", owner: "acme", ecosystem: "Go", dependency: "gitlab.com/acme/lib", matches: true, kind: .gitLab),
        Case(type: .golang, published: "gitlab.com/acme/lib", owner: "acme", ecosystem: "Go", dependency: "gitlab.com/acme/lib/v2", matches: false, kind: .gitLab),
        // NuGet: zonder verschil tussen hoofd- en kleine letters.
        Case(type: .nuGet, published: "Acme.Core", owner: "acme", ecosystem: "NuGet", dependency: "acme.core", matches: true),
        Case(type: .nuGet, published: "acme.core", owner: "acme", ecosystem: "NuGet", dependency: "Acme.Core", matches: true),
        Case(type: .nuGet, published: "Acme.Core", owner: "acme", ecosystem: "NuGet", dependency: "Acme.Core.Extra", matches: false),
        // Maven: groupId:artifactId, zoals GitHub (punten), GitLab (pad) of Azure (dubbele punt) het schrijft.
        Case(type: .maven, published: "com.acme:ui-kit", owner: "acme", ecosystem: "Maven", dependency: "com.acme:ui-kit", matches: true),
        Case(type: .maven, published: "com.acme.ui-kit", owner: "acme", ecosystem: "Maven", dependency: "com.acme:ui-kit", matches: true),
        Case(type: .maven, published: "com/acme/ui-kit", owner: "acme", ecosystem: "Maven", dependency: "com.acme:ui-kit", matches: true),
        Case(type: .maven, published: "com.acme:ui-kit", owner: "acme", ecosystem: "Maven", dependency: "com.acme:core", matches: false),
        // PyPI: zoals PEP 503.
        Case(type: .pyPI, published: "Acme_Tools", owner: "acme", ecosystem: "PyPI", dependency: "acme-tools", matches: true),
        Case(type: .pyPI, published: "acme.tools", owner: "acme", ecosystem: "PyPI", dependency: "ACME_tools", matches: true),
        Case(type: .pyPI, published: "acme-tools", owner: "acme", ecosystem: "PyPI", dependency: "acme-tool", matches: false),
        // RubyGems.
        Case(type: .rubyGems, published: "acme-client", owner: "acme", ecosystem: "RubyGems", dependency: "acme-client", matches: true),
        // Een ander ecosysteem met dezelfde naam, of een image: nooit.
        Case(type: .npm, published: "@acme/ui", owner: "acme", ecosystem: "NuGet", dependency: "@acme/ui", matches: false),
        Case(type: .container, published: "acme/web", owner: "acme", ecosystem: "npm", dependency: "acme/web", matches: false),
    ]

    @Test(arguments: cases)
    func `Matches a dependency to a published package per ecosystem`(_ item: Case) {
        let package = PublishedPackage(accountId: fixedAccountId, name: item.published, type: item.type, owner: item.owner, repository: "acme/lib")

        let found = InHouseIndex([package], kinds: [fixedAccountId: item.kind]).match(ecosystem: item.ecosystem, name: item.dependency)

        #expect((found != nil) == item.matches)
    }

    @Test func `The in-house latest is the normalised version, never a floating tag`() throws {
        let floating = PublishedPackage(
            accountId: fixedAccountId, name: "ui", type: .npm, owner: "acme", repository: "acme/ui", latestVersion: "main",
            latestKind: .floatingTag
        )
        let released = PublishedPackage(
            accountId: fixedAccountId, name: "ui", type: .npm, owner: "acme", repository: "acme/ui", latestVersion: "2.4.0-rc1",
            versions: [PublishedVersion(version: "2.4.0-rc1"), PublishedVersion(version: "v2.3.0"), PublishedVersion(version: "2.2.0")]
        )

        #expect(VersionChecker.metadata(of: floating, repositoryURL: nil) == nil, "zonder nieuwste versie geen eigen metadata")
        #expect(try #require(VersionChecker.metadata(of: released, repositoryURL: nil)).latest == "v2.3.0", "de hoogste stabiele versie")
    }

    @Test func `An Azure package links to the project of its feed`() {
        let account = Account(id: fixedAccountId, kind: .azureDevOps, organization: "contoso", authMethod: .pat)
        let package = PublishedPackage(accountId: fixedAccountId, name: "acme-ui", type: .npm, owner: "Platform", repository: nil)
        let orgFeed = PublishedPackage(accountId: fixedAccountId, name: "acme-ui", type: .npm, owner: "contoso", repository: nil)

        #expect(VersionChecker.projectURL(package, account: account) == URL(string: "https://dev.azure.com/contoso/Platform"))
        #expect(VersionChecker.projectURL(orgFeed, account: account) == URL(string: "https://dev.azure.com/contoso"))
    }

    // MARK: - Lezen

    @Test func `Metadata from an older report has no in-house marker`() throws {
        let json = #"{"latest":"1.0.0","versions":{"1.0.0":{}}}"#

        let metadata = try JSONDecoder().decode(PackageMetadata.self, from: Data(json.utf8))

        #expect(metadata.latest == "1.0.0")
        #expect(metadata.inHouse == nil)
    }

    @Test func `A broken in-house marker does not break the metadata`() throws {
        let json = #"{"latest":"1.0.0","versions":{},"inHouse":{"name":"@acme/ui"}}"#

        let metadata = try JSONDecoder().decode(PackageMetadata.self, from: Data(json.utf8))

        #expect(metadata.latest == "1.0.0")
        #expect(metadata.inHouse == nil)
    }

    @Test func `An unknown status reads as not checked`() throws {
        let json = #"{"accountId":"\#(fixedAccountId.uuidString)","name":"ui","type":"npm","owner":"acme","status":"somethingNew"}"#

        let inHouse = try JSONDecoder().decode(InHousePackage.self, from: Data(json.utf8))

        #expect(inHouse.status == InHousePackage.Status.sourceOff)
        #expect(inHouse.repository == nil)
        #expect(inHouse.source == "acme")
    }

    @Test(arguments: [InHousePackage.Status.checked, .sourceOff, .needsPermission(reason: "read:packages"), .readFailed, .unconfirmed])
    func `The marker survives a round trip`(status: InHousePackage.Status) throws {
        let inHouse = InHousePackage(
            accountId: fixedAccountId, name: "ui", type: .npm, owner: "acme", repository: "acme/ui",
            repositoryURL: URL(string: "https://github.com/acme/ui"), registryURL: URL(string: "https://github.com/orgs/acme/packages/npm/package/ui"),
            status: status
        )
        let metadata = PackageMetadata(latest: "2.3.0", versions: ["2.3.0": VersionMetadata()], inHouse: inHouse)

        let decoded = try JSONDecoder().decode(PackageMetadata.self, from: JSONEncoder().encode(metadata))

        #expect(decoded == metadata)
    }

    @Test func `A report from before in-house packages still reads`() throws {
        let json = #"{"checkedAt":0,"repos":[],"packageMetadata":{"npm:lodash":{"latest":"4.17.21","versions":{}}}}"#

        let report = try JSONDecoder().decode(VersionReport.self, from: Data(json.utf8))

        #expect(report.packageMetadata["npm:lodash"]?.inHouse == nil)
        #expect(report.packageSummaries().allSatisfy { $0.inHouse == nil })
    }
}
