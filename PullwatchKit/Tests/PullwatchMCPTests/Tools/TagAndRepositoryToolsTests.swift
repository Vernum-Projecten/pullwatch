import Foundation
import MCP
import PullwatchCore
import PullwatchMCP
import Testing

/// `list_tags`, `list_repositories` en `get_repository_report` over de fixtures.
@Suite struct TagAndRepositoryToolsTests {
    let harness = ToolHarness()

    // MARK: - list_tags

    @Test func `Lists the tags of followed repositories with their release, newest first`() async throws {
        let output = try await harness.output("list_tags")

        let tags = output["tags"]?.objects ?? []
        #expect(tags.compactMap { $0["name"]?.stringValue } == ["v1.2.0", "v1.1.0"])
        #expect(output["total"] == 2)
        #expect(tags.first?["release"] == [
            "title": "Spring release", "is_prerelease": false, "published_at": "2026-11-03T12:00:00Z",
            "url": "https://github.com/acme/web/releases/tag/v1.2.0",
        ])
        #expect(tags.last?["release"] == nil)
        #expect(tags.first?["is_read"] == false)
    }

    @Test(arguments: [
        (["unread": true], ["v1.2.0", "v1.1.0"]),
        (["unread": false], []),
        (["repo": "acme/web", "limit": 1], ["v1.2.0"]),
    ] as [([String: Value], [String])])
    func `Tag filters and paging narrow the list`(arguments: [String: Value], expected: [String]) async throws {
        let output = try await harness.output("list_tags", arguments)

        #expect(output["tags"]?.objects.compactMap { $0["name"]?.stringValue } == expected)
    }

    @Test func `Tags of a repository that is not followed never appear`() async throws {
        let wire = try await harness.wire("list_tags")
        #expect(!wire.contains("v0.9.0"))

        let message = try await harness.error("list_tags", ["repo": "acme/old"])
        #expect(message == "Repository acme/old is not followed in Pullwatch. list_repositories lists the repositories you can ask about.")
    }

    // MARK: - list_repositories

    @Test func `Lists followed repositories worst first with their counts`() async throws {
        let output = try await harness.output("list_repositories")

        let repos = output["repositories"]?.objects ?? []
        #expect(repos.compactMap { $0["repository"]?.stringValue } == ["acme/web", "group/app", "acme/api"])
        #expect(output["checked_at"] == "2026-11-03T10:00:00Z")
        let web = try #require(repos.first)
        #expect(web["health"] == "problem")
        #expect(web["checked"] == true)
        #expect(web["open_pull_requests"] == 5)
        #expect(web["latest_tag"] == "v1.2.0")
        #expect(web["vulnerabilities"] == 1)
        #expect(web["vulnerabilities_by_severity"] == ["critical": 0, "high": 1, "moderate": 0, "low": 0, "unknown": 0])
        #expect(web["serious_security_alerts"] == 1)
        #expect(web["open_secrets"] == 2)
        #expect(web["outdated_runtimes"] == 1)
        #expect(web["url"] == "https://github.com/acme/web")
    }

    @Test func `A repository whose registry is off is unknown, never ok`() async throws {
        let output = try await harness.output("list_repositories", ["health": "unknown"])

        let app = try #require(output["repositories"]?.objects.first)
        #expect(app["repository"] == "group/app")
        #expect(app["not_checked"] == [["source": "pyPI", "message": "Not checked: source PyPI is off."]])
    }

    @Test func `Vulnerability counts are absent while OSV is off`() async throws {
        var harness = harness
        harness.source.disabled = [.osv]

        let output = try await harness.output("list_repositories", ["limit": 1])

        let web = try #require(output["repositories"]?.objects.first)
        #expect(web["vulnerabilities"] == nil)
        #expect(web["vulnerabilities_by_severity"] == nil)
        #expect(web["not_checked"]?.arrayValue?.contains(["source": "osv", "message": "Not checked: source OSV.dev is off."]) == true)
        #expect(output["next_cursor"] == "1")
    }

    @Test func `A repository that is not followed is not listed`() async throws {
        let wire = try await harness.wire("list_repositories", ["limit": 100])

        #expect(!wire.contains("acme/old"))
    }

    // MARK: - get_repository_report

    @Test func `The report lists runtimes and packages with their update state`() async throws {
        let output = try await harness.output("get_repository_report", ["repo": "acme/web"])

        #expect(output["checked"] == true)
        #expect(output["runtimes"] == [[
            "name": "Node.js", "product": "nodejs", "version": "18", "latest": "22", "status": "end_of_life", "declared_in": [".nvmrc"],
        ]])
        let packages = output["packages"]?.objects ?? []
        #expect(packages.compactMap { $0["name"]?.stringValue } == ["express", "left-pad", "body-parser"])
        let express = try #require(packages.first)
        #expect(express["update"] == "needs_manifest_change")
        #expect(express["latest"] == "5.1.0")
        #expect(express["blocker"] == "express 5.1.0 needs a new major version (outside ^4.19.0).")
        #expect(packages[1]["update"] == "up_to_date")
        #expect(packages[2]["group"] == "transitive")
    }

    @Test func `only_outdated keeps the packages with a newer version`() async throws {
        let output = try await harness.output("get_repository_report", ["repo": "acme/web", "only_outdated": true])

        #expect(output["packages"]?.objects.compactMap { $0["name"]?.stringValue } == ["express", "body-parser"])
        #expect(output["total"] == 2)
    }

    @Test func `Packages of a registry that is off are not checked`() async throws {
        let output = try await harness.output("get_repository_report", ["repo": "group/app"])

        let requests = try #require(output["packages"]?.objects.first)
        #expect(requests["update"] == "not_checked")
        #expect(requests["latest"] == nil)
        #expect(output["not_checked"] == [["source": "pyPI", "message": "Not checked: source PyPI is off."]])
    }

    @Test func `A runtime whose release source is off is not checked`() async throws {
        var harness = harness
        harness.source.disabled = [.endOfLife]

        let output = try await harness.output("get_repository_report", ["repo": "acme/web"])

        #expect(output["runtimes"]?.objects.first?["status"] == "not_checked")
        #expect(output["runtimes"]?.objects.first?["latest"] == nil)
    }

    @Test func `A followed repository that was never checked says so`() async throws {
        var harness = harness
        harness.source.accountList[0].repoWatch["acme/new"] = .prs

        let output = try await harness.output("get_repository_report", ["repo": "acme/new"])

        #expect(output["checked"] == false)
        #expect(output["health"] == "unknown")
        #expect(output["packages"] == [])
    }

    @Test func `Packages are paged`() async throws {
        let output = try await harness.output("get_repository_report", ["repo": "acme/web", "limit": 2])

        #expect(output["packages"]?.arrayValue?.count == 2)
        #expect(output["total"] == 3)
        #expect(output["next_cursor"] == "2")
    }
}
