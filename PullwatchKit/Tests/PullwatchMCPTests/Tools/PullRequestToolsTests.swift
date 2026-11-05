import Foundation
import MCP
import PullwatchCore
import PullwatchMCP
import Testing

/// `list_pull_requests` en `get_pull_request` over de geschiedenis van de fixtures.
@Suite struct PullRequestToolsTests {
    let harness = ToolHarness()

    func numbers(_ output: [String: Value]) -> [Int] {
        output["pull_requests"]?.objects.compactMap { $0["number"]?.intValue } ?? []
    }

    // MARK: - list_pull_requests

    @Test func `Lists the open pull requests of followed repositories, newest first`() async throws {
        let output = try await harness.output("list_pull_requests")

        #expect(numbers(output) == [1, 2, 3, 6, 7, 10])
        #expect(output["total"] == 6)
        #expect(output["next_cursor"] == nil)
        #expect(output["not_checked"] == [])
        let first = try #require(output["pull_requests"]?.objects.first)
        #expect(first["repository"] == "acme/web")
        #expect(first["reference"] == "acme/web#1")
        #expect(first["account_id"] == .string(FakeDataSource.gitHubId.uuidString))
        #expect(first["title"] == "Add login")
        #expect(first["state"] == "open")
        #expect(first["is_mine"] == true)
        #expect(first["is_read"] == false)
        #expect(first["created_at"] == "2026-11-03T20:00:00Z")
        #expect(first["url"] == "https://github.com/acme/web/pull/1")
        #expect(first["checks"] == ["status": "failed", "passed": 3, "failed": 1, "pending": 0, "skipped": 0, "total": 4])
    }

    @Test(arguments: [
        ("draft", [2]),
        ("queued", [3]),
        ("merged", [4]),
        ("closed", [5]),
        ("all", [1, 2, 3, 4, 5, 6, 7, 10]),
    ])
    func `Filters by state`(state: String, expected: [Int]) async throws {
        let output = try await harness.output("list_pull_requests", ["state": .string(state)])

        #expect(numbers(output) == expected)
    }

    @Test(arguments: [
        (["checks": "failed"], [1]),
        (["checks": "pending"], [6]),
        (["checks": "passed"], [3]),
        (["mine": true], [1]),
        (["mine": false], [2, 3, 6, 7, 10]),
        (["author": "ADA"], [2, 3]),
        (["unread": false, "state": "all"], [4, 5]),
        (["repo": "group/app"], [10]),
        (["repo": "ACME/WEB", "author": "bob"], [6, 7]),
        (["account_id": .string(FakeDataSource.gitLabId.uuidString)], [10]),
    ] as [([String: Value], [Int])])
    func `Filters narrow the list`(arguments: [String: Value], expected: [Int]) async throws {
        let output = try await harness.output("list_pull_requests", arguments)

        #expect(numbers(output) == expected)
    }

    @Test func `Queued pull requests carry their place in the queue`() async throws {
        let output = try await harness.output("list_pull_requests", ["state": "queued"])

        let queued = try #require(output["pull_requests"]?.objects.first)
        #expect(queued["is_queued"] == true)
        #expect(queued["merge_queue"] == ["kind": "merge_queue", "position": 1, "enqueued_at": "2026-11-03T10:00:00Z"])
    }

    @Test func `A pull request that left the queue says so and why`() async throws {
        let output = try await harness.output("get_pull_request", ["repo": "acme/web", "number": 6])

        let pr = try #require(output["pull_request"])
        #expect(pr["has_left_queue"] == true)
        #expect(pr["is_queued"] == false)
        #expect(pr["left_queue"] == [
            "kind": "merge_queue", "at": "2026-11-03T10:00:00Z", "reason": "The merge commit failed its checks",
        ])
        let wire = try await harness.wire("get_pull_request", ["repo": "acme/web", "number": 6])
        #expect(wire.contains("left the queue without merging: The merge commit failed its checks"))
    }

    @Test func `A pull request that never left a queue has no left_queue`() async throws {
        let output = try await harness.output("get_pull_request", ["repo": "acme/web", "number": 3])

        let pr = try #require(output["pull_request"])
        #expect(pr["has_left_queue"] == false)
        #expect(pr["left_queue"] == nil)
    }

    @Test func `Pages through the list with limit and cursor`() async throws {
        let first = try await harness.output("list_pull_requests", ["state": "all", "limit": 3])
        #expect(numbers(first) == [1, 2, 3])
        #expect(first["total"] == 8)
        let cursor = try #require(first["next_cursor"])

        let second = try await harness.output("list_pull_requests", ["state": "all", "limit": 3, "cursor": cursor])
        #expect(numbers(second) == [4, 5, 6])
        let third = try await harness.output("list_pull_requests", ["state": "all", "limit": 3, "cursor": try #require(second["next_cursor"])])
        #expect(numbers(third) == [7, 10])
        #expect(third["next_cursor"] == nil)
    }

    @Test func `A cursor that is not from the tool is a tool error`() async throws {
        let message = try await harness.error("list_pull_requests", ["cursor": "page-two"])

        #expect(message == "`cursor` is not a cursor from this tool; pass the next_cursor of the previous page, or leave it out for the first page.")
    }

    @Test func `A limit above the maximum is a tool error that names the field`() async throws {
        let message = try await harness.error("list_pull_requests", ["limit": 500])

        #expect(message == "Invalid arguments for list_pull_requests: `limit` must be at most 100.")
    }

    @Test func `Checks are not checked while the CI checks source is off`() async throws {
        var harness = harness
        harness.source.disabled = [.ciChecks]

        let output = try await harness.output("list_pull_requests")

        let checks = output["pull_requests"]?.objects.compactMap { $0["checks"] } ?? []
        #expect(checks.count == 6)
        #expect(checks.allSatisfy { $0 == ["status": "not_checked", "message": "Not checked: source CI checks is off."] })
        #expect(output["not_checked"] == [["source": "ciChecks", "message": "Not checked: source CI checks is off."]])
    }

    @Test func `Filtering by checks while the CI checks source is off says why`() async throws {
        var harness = harness
        harness.source.disabled = [.ciChecks]

        let message = try await harness.error("list_pull_requests", ["checks": "failed"])

        #expect(message == "Not checked: source CI checks is off. Pull requests cannot be filtered by checks; leave out the checks filter.")
    }

    @Test(arguments: ["not_fetched", "needs_permission"])
    func `Checks without counts say why`(status: String) async throws {
        let output = try await harness.output("list_pull_requests")

        let pr = try #require(output["pull_requests"]?.objects.first { $0["checks"]?["status"] == .string(status) })
        #expect(pr["checks"]?["message"]?.stringValue?.isEmpty == false)
        #expect(pr["checks"]?["total"] == nil)
    }

    @Test func `A GitLab merge request is referenced with an exclamation mark`() async throws {
        let output = try await harness.output("list_pull_requests", ["repo": "group/app"])

        let pr = try #require(output["pull_requests"]?.objects.first)
        #expect(pr["number"] == 10)
        #expect(pr["reference"] == "group/app!10")
    }

    @Test func `get_pull_request gives the reference of a GitLab merge request`() async throws {
        let output = try await harness.output("get_pull_request", ["repo": "group/app", "number": 10])

        #expect(output["pull_request"]?["reference"] == "group/app!10")
    }

    // MARK: - get_pull_request

    @Test func `Gets one pull request with its co-authors but no e-mail address`() async throws {
        let output = try await harness.output("get_pull_request", ["repo": "acme/web", "number": 1])

        let pr = try #require(output["pull_request"])
        #expect(pr["number"] == 1)
        #expect(pr["reference"] == "acme/web#1")
        #expect(pr["co_authors"] == ["ada"])
        let wire = try await harness.wire("get_pull_request", ["repo": "acme/web", "number": 1])
        #expect(!wire.contains("ada@example.com"))
    }

    @Test func `A pull request that is not in the history is a tool error`() async throws {
        let message = try await harness.error("get_pull_request", ["repo": "acme/web", "number": 42])

        #expect(message == "Pull request #42 of acme/web is not in Pullwatch's history. list_pull_requests with repo acme/web and state all lists the ones it has.")
    }

    @Test(arguments: ["acme/old", "evil/other"])
    func `A repository that is not followed does not exist`(repo: String) async throws {
        let message = try await harness.error("get_pull_request", ["repo": .string(repo), "number": 99])

        #expect(message == "Repository \(repo) is not followed in Pullwatch. list_repositories lists the repositories you can ask about.")
    }

    @Test func `Pull requests of a repository that is not followed never appear`() async throws {
        let wire = try await harness.wire("list_pull_requests", ["state": "all", "limit": 100])

        #expect(!wire.contains("acme/old"))
        #expect(!wire.contains("Hidden change"))
    }

    @Test func `A repository two accounts follow needs an account id`() async throws {
        let second = Account(id: UUID(), kind: .gitHub, organization: "acme", authMethod: .cli, repoWatch: ["acme/web": .prs])
        var harness = harness
        harness.source.accountList.append(second)

        let message = try await harness.error("get_pull_request", ["repo": "acme/web", "number": 1])
        #expect(message == "Repository acme/web is followed by more than one account (\(FakeDataSource.gitHubId.uuidString), \(second.id.uuidString)); pass account_id to choose one.")

        let output = try await harness.output(
            "get_pull_request", ["repo": "acme/web", "number": 1, "account_id": .string(FakeDataSource.gitHubId.uuidString)]
        )
        #expect(output["pull_request"]?["number"] == 1)
    }
}
