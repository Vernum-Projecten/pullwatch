import Foundation
import MCP
import PullwatchCore
import PullwatchMCP
import Testing

/// `list_packages` over de fixtures: wat de gevolgde repo's publiceren, bladeren, de filters, de
/// bron die uit staat en een account zonder recht.
@Suite struct ListPackagesToolTests {
    let harness = ToolHarness()

    @Test func `Lists the published packages of followed repositories, with their versions`() async throws {
        let output = try await harness.output("list_packages")

        let packages = output["packages"]?.objects ?? []
        #expect(packages.map { $0["name"] } == ["api", "shared", "ui"])
        let ui = try #require(packages.last)
        #expect(ui["type"] == "npm")
        #expect(ui["repository"] == "acme/web")
        #expect(ui["latest_version"] == "2.3.0")
        #expect(ui["visibility"] == "private")
        #expect(ui["url"] == "https://github.com/orgs/acme/packages/npm/package/ui")
        #expect(ui["recent_versions"]?.objects.map { $0["version"] } == ["2.3.0", "2.2.0"])
        #expect(ui["recent_versions"]?.objects.first?["tag"] == "v2.3.0")
        #expect(ui["usage_known"] == true)
        #expect(packages.first?["usage_known"] == false)
        #expect(packages[1]["repository"] == nil)
        #expect(output["total"] == 3)
        #expect(output["not_checked"] == [])
    }

    @Test func `An account without permission is listed with its reason, never as publishing nothing`() async throws {
        let output = try await harness.output("list_packages")

        let needs = output["needs_permission"]?.objects ?? []
        #expect(needs.count == 1)
        #expect(needs.first?["account_id"] == .string(FakeDataSource.gitLabId.uuidString))
        #expect(needs.first?["reason"] == "Needs read_api.")
    }

    @Test func `Pages with limit and cursor`() async throws {
        let first = try await harness.output("list_packages", ["limit": 2])
        #expect(first["packages"]?.objects.count == 2)
        let cursor = try #require(first["next_cursor"]?.stringValue)

        let second = try await harness.output("list_packages", ["limit": 2, "cursor": .string(cursor)])
        #expect(second["packages"]?.objects.map { $0["name"] } == ["ui"])
        #expect(second["next_cursor"] == nil)
    }

    @Test(arguments: [("npm", ["shared", "ui"]), ("container", ["api"]), ("nuget", [])])
    func `type keeps only that type`(type: String, names: [String]) async throws {
        let output = try await harness.output("list_packages", ["type": .string(type)])

        #expect(output["packages"]?.objects.compactMap { $0["name"]?.stringValue } == names)
    }

    @Test func `repo keeps what that repository publishes`() async throws {
        let output = try await harness.output("list_packages", ["repo": "acme/web"])

        #expect(output["packages"]?.objects.map { $0["name"] } == ["ui"])
    }

    @Test func `With the source off nothing is listed and the source is named`() async throws {
        var harness = harness
        harness.source.disabled = [.packageRegistries]

        let output = try await harness.output("list_packages")

        #expect(output["packages"] == [])
        let off = try #require(output["not_checked"]?.objects.first)
        #expect(off["source"] == "packageRegistries")
        #expect(off["message"]?.stringValue?.hasPrefix("Not checked: source") == true)
    }

    @Test func `Used by names the followed repositories on each version`() async throws {
        var harness = harness
        let report = FakeDataSource.report
        let ui = try #require(FakeDataSource.publishedPackages.first)
        let inHouse = InHousePackage(accountId: ui.accountId, name: ui.name, type: ui.type, owner: ui.owner, repository: ui.repository)
        var metadata = report.packageMetadata
        metadata["npm:express"] = PackageMetadata(latest: "2.3.0", versions: [:], inHouse: inHouse)
        harness.source.report = VersionReport(
            checkedAt: report.checkedAt, repos: report.repos, latestPackages: report.latestPackages,
            packageMetadata: metadata, publishedPackages: report.publishedPackages
        )

        let output = try await harness.output("list_packages", ["repo": "acme/web"])

        let users = output["packages"]?.objects.first?["used_by"]?.objects ?? []
        #expect(users.map { $0["repository"] } == ["acme/web"])
        #expect(users.first?["versions"] == ["4.19.2"])
        #expect(users.first?["is_direct"] == true)
    }
}
