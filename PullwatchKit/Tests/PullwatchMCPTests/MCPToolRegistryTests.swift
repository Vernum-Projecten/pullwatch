import Foundation
import MCP
@testable import PullwatchMCP
import Testing

/// Het register weigert een tool die de specificatie niet toestaat.
@Suite struct MCPToolRegistryTests {
    static func tool(_ name: String, input: MCPSchema = .object([:]), output: MCPSchema = .object([:])) -> MCPTool {
        MCPTool(name: name, description: "Test.", input: input, output: output) { _ in
            MCPToolResult(structuredContent: [:], summary: "")
        }
    }

    @Test(arguments: ["", "list tags", "lijst_met_één", String(repeating: "a", count: 129)])
    func `An invalid tool name is refused`(name: String) {
        #expect(throws: MCPToolRegistry.InvalidTool(name: name, reason: "invalid name")) {
            try MCPToolRegistry([Self.tool(name)])
        }
    }

    @Test func `Valid tool names are accepted`() throws {
        let registry = try MCPToolRegistry([Self.tool("list_tags"), Self.tool("get-status.v2"), Self.tool(String(repeating: "a", count: 128))])
        #expect(registry.definitions.count == 3)
    }

    @Test func `A duplicate tool name is refused`() {
        #expect(throws: MCPToolRegistry.InvalidTool(name: "list_tags", reason: "duplicate name")) {
            try MCPToolRegistry([Self.tool("list_tags"), Self.tool("list_tags")])
        }
    }

    @Test func `Schemas that are not objects are refused`() {
        #expect(throws: MCPToolRegistry.InvalidTool(name: "a", reason: "input schema is not an object")) {
            try MCPToolRegistry([Self.tool("a", input: .string())])
        }
        #expect(throws: MCPToolRegistry.InvalidTool(name: "b", reason: "output schema is not an object")) {
            try MCPToolRegistry([Self.tool("b", output: .array(of: .string()))])
        }
    }

    @Test func `Arguments nested too deep are refused before the schema`() async throws {
        let registry = try MCPToolRegistry(
            [Self.tool("a", input: .dictionary(of: .array(of: .array(of: .integer()))))],
            limits: MCPLimits(maxMessageBytes: 1024, maxDepth: 2)
        )

        let result = try await registry.call("a", arguments: ["x": [[1]]])

        #expect(result.isError == true)
        #expect(result.content == [.text(text: "Invalid arguments for a: they are nested deeper than 2 levels.", annotations: nil, _meta: nil)])
        #expect(result.structuredContent == nil)
    }

    @Test func `A tool can decode its arguments into a type`() throws {
        struct Filters: Decodable, Equatable {
            let repo: String
            let limit: Int?
        }
        let arguments = MCPArguments(["repo": "acme/web", "limit": 3])
        #expect(try arguments.decode(as: Filters.self) == Filters(repo: "acme/web", limit: 3))
        let error = #expect(throws: MCPToolError.self) {
            try MCPArguments(["limit": 3]).decode(as: Filters.self)
        }
        #expect(error?.message.hasPrefix("The arguments do not fit: ") == true)
    }

    @Test func `Output from an Encodable value is a JSON object with ISO dates`() throws {
        struct Output: Encodable {
            let repo: String
            let updated: Date
        }
        let result = try MCPToolResult(encoding: Output(repo: "acme/web", updated: Date(timeIntervalSince1970: 0)), summary: "One.")
        #expect(result.structuredContent == ["repo": "acme/web", "updated": "1970-01-01T00:00:00Z"])
        #expect(throws: MCPError.self) {
            try MCPToolResult(encoding: ["a", "b"], summary: "Not an object.")
        }
    }
}
