import Foundation
import MCP
import PullwatchCore
import PullwatchMCP
import Testing

/// `explain_update` en `get_repository_report` over een eigen package: acme/web gebruikt @acme/ui,
/// dat acme/ui zelf in GitHub Packages publiceert.
@Suite struct InHouseToolsTests {
    static func report(status: InHousePackage.Status = .checked) -> VersionReport {
        let checkedAt = FakeDataSource.checkedAt
        let inHouse = InHousePackage(
            accountId: FakeDataSource.gitHubId, name: "ui", type: .npm, owner: "acme", repository: "acme/ui",
            repositoryURL: URL(string: "https://github.com/acme/ui"),
            registryURL: URL(string: "https://github.com/orgs/acme/packages/npm/package/ui"), status: status
        )
        let checked = status == .checked
        return VersionReport(
            checkedAt: checkedAt,
            repos: [RepoVersions(
                accountId: FakeDataSource.gitHubId, repo: "acme/web", components: [],
                packages: [PackageUse(ecosystem: "npm", name: "@acme/ui", installs: [
                    PackageInstall(version: "2.1.0", workspace: "", scope: .direct, source: "package-lock.json", requested: "^2.1.0"),
                ])],
                skippedSources: status == .sourceOff ? [.packageRegistries] : []
            )],
            latestPackages: checked ? ["npm:@acme/ui": PackageLatest(version: "2.3.0", seenAt: checkedAt)] : [:],
            packageMetadata: ["npm:@acme/ui": checked
                ? PackageMetadata(latest: "2.3.0", versions: ["2.1.0": VersionMetadata(), "2.3.0": VersionMetadata()], inHouse: inHouse)
                : PackageMetadata(latest: nil, versions: [:], inHouse: inHouse)]
        )
    }

    func harness(_ status: InHousePackage.Status = .checked, disabled: Set<DataSourceID> = []) -> ToolHarness {
        var source = FakeDataSource()
        source.report = Self.report(status: status)
        source.disabled = disabled
        return ToolHarness(source: source)
    }

    // MARK: - explain_update

    @Test func `Explains an in-house package with its source and latest version from your own registry`() async throws {
        let output = try await harness().output("explain_update", ["repo": "acme/web", "package": "@acme/ui"])

        #expect(output["latest"] == "2.3.0")
        let inHouse = try #require(output["in_house"])
        #expect(inHouse["source"] == "acme/ui")
        #expect(inHouse["repository"] == "acme/ui")
        #expect(inHouse["owner"] == "acme")
        #expect(inHouse["url"] == "https://github.com/acme/ui")
        #expect(inHouse["registry_url"] == "https://github.com/orgs/acme/packages/npm/package/ui")
        #expect(inHouse["status"] == "checked")
        let install = try #require(output["installs"]?.objects.first)
        #expect(install["update"] == "within_range")
        #expect(output["not_checked"] == [])
    }

    @Test func `The public npm switch does not hide an in-house package`() async throws {
        let output = try await harness(disabled: [.npm]).output("explain_update", ["repo": "acme/web", "package": "@acme/ui"])

        #expect(output["latest"] == "2.3.0")
        #expect(output["installs"]?.objects.first?["update"] == "within_range")
    }

    @Test func `With the source off an in-house package is not checked`() async throws {
        let output = try await harness(.sourceOff).output("explain_update", ["repo": "acme/web", "package": "@acme/ui"])

        #expect(output["latest"] == nil)
        #expect(output["in_house"]?["status"] == "source_off")
        let install = try #require(output["installs"]?.objects.first)
        #expect(install["update"] == "not_checked")
        #expect(install["explanation"] == .string(
            "@acme/ui 2.1.0 in the root: the latest version is not checked because the source Package registries of your accounts is off."
        ))
        #expect(output["not_checked"]?.objects.first?["message"] == "Not checked: source Package registries of your accounts is off.")
    }

    @Test func `Without permission an in-house package names the missing permission`() async throws {
        let output = try await harness(.needsPermission(reason: "Add read:packages.")).output(
            "explain_update", ["repo": "acme/web", "package": "@acme/ui"]
        )

        #expect(output["in_house"]?["status"] == "needs_permission")
        #expect(output["in_house"]?["reason"] == "Add read:packages.")
        #expect(output["installs"]?.objects.first?["update"] == "not_checked")
        #expect(output["not_checked"]?.objects.first?["message"]
            == "Not checked: Pullwatch has no permission to read this account's package registry (Add read:packages.).")
    }

    @Test func `An in-house package only the lockfile names is not checked`() async throws {
        let output = try await harness(.unconfirmed).output("explain_update", ["repo": "acme/web", "package": "@acme/ui"])

        #expect(output["latest"] == nil)
        #expect(output["in_house"]?["status"] == "unconfirmed")
        #expect(output["installs"]?.objects.first?["update"] == "not_checked")
        #expect(output["not_checked"]?.objects.first?["message"]
            == "Not checked: the lockfile installs it from this account's own package registry, but that registry did not list it.")
    }

    // MARK: - get_repository_report

    @Test func `The report marks an in-house package`() async throws {
        let output = try await harness().output("get_repository_report", ["repo": "acme/web"])

        let package = try #require(output["packages"]?.objects.first { $0["name"] == "@acme/ui" })
        #expect(package["latest"] == "2.3.0")
        #expect(package["update"] == "within_range")
        #expect(package["in_house"]?["source"] == "acme/ui")
        #expect(package["in_house"]?["status"] == "checked")
    }

    @Test func `The report never calls an unchecked in-house package up to date`() async throws {
        let output = try await harness(.needsPermission(reason: "")).output("get_repository_report", ["repo": "acme/web"])

        let package = try #require(output["packages"]?.objects.first { $0["name"] == "@acme/ui" })
        #expect(package["update"] == "not_checked")
        #expect(package["in_house"]?["status"] == "needs_permission")
        #expect(output["not_checked"]?.objects.contains { $0["source"] == "packageRegistries" } == true)
    }
}
