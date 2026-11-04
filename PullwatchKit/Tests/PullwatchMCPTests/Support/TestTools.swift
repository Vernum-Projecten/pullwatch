import Foundation
import MCP
import PullwatchMCP

/// Tools die alleen de tests kennen: één die zijn argumenten teruggeeft, en één per manier waarop
/// een tool fout kan gaan.
enum TestTools {
    static let describeRepo = MCPTool(
        name: "describe_repo",
        title: "Describe a repository",
        description: "Returns the repository, state and limit it was asked for.",
        input: .object(
            [
                "repo": .string("Repository as owner/name.", maxLength: 100),
                "state": .string("Pull request state.", oneOf: ["open", "closed"]),
                "limit": .integer("Most results.", minimum: 1, maximum: 50),
                "labels": .array(of: .string(), "Labels to match.", maxItems: 3),
            ],
            required: ["repo"]
        ),
        output: .object(
            ["repo": .string(), "state": .string(), "limit": .integer()],
            required: ["repo", "state", "limit"]
        )
    ) { arguments in
        let repo = arguments.string("repo") ?? ""
        return MCPToolResult(
            structuredContent: [
                "repo": .string(repo),
                "state": .string(arguments.string("state") ?? "open"),
                "limit": .int(arguments.integer("limit") ?? 20),
            ],
            summary: "Repository \(repo)."
        )
    }

    /// Gooit een fout voor het model.
    static let notFollowed = MCPTool(
        name: "not_followed",
        description: "Always says the repository is not followed.",
        output: .object([:])
    ) { _ in
        throw MCPToolError("Repository acme/secret is not followed in Pullwatch.")
    }

    /// Gooit een fout van binnen, met details die niet naar het model mogen.
    static let crashing = MCPTool(
        name: "crashing",
        description: "Always fails inside.",
        output: .object([:])
    ) { _ in
        throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: "/Users/someone/private.json"])
    }

    /// Geeft uitvoer die niet bij zijn eigen schema past.
    static let wrongOutput = MCPTool(
        name: "wrong_output",
        description: "Returns output without its required field.",
        output: .object(["count": .integer()], required: ["count"])
    ) { _ in
        MCPToolResult(structuredContent: ["total": 3], summary: "3.")
    }

    static func registry() throws -> MCPToolRegistry {
        try MCPToolRegistry([describeRepo, notFollowed, crashing, wrongOutput])
    }
}
