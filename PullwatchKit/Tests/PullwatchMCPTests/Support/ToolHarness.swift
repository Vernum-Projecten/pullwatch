import Foundation
import MCP
import PullwatchMCP
import Testing

/// Roept de echte tools aan zoals de server dat doet (`MCPToolRegistry.call`, dus met de controle
/// van invoer en uitvoer tegen hun schema), over een `FakeDataSource`.
struct ToolHarness {
    var source = FakeDataSource()

    func call(_ name: String, _ arguments: [String: Value] = [:]) async throws -> CallTool.Result {
        try await PullwatchMCPTools.registry(dataSource: source).call(name, arguments: arguments)
    }

    /// De gestructureerde uitvoer van een geslaagde aanroep.
    func output(_ name: String, _ arguments: [String: Value] = [:]) async throws -> [String: Value] {
        let result = try await call(name, arguments)
        #expect(result.isError == false, "\(name) failed: \(Self.texts(result))")
        return try #require(result.structuredContent?.objectValue)
    }

    /// De melding van een aanroep die als fout van de tool terugkomt.
    func error(_ name: String, _ arguments: [String: Value] = [:]) async throws -> String {
        let result = try await call(name, arguments)
        #expect(result.isError == true)
        #expect(result.structuredContent == nil)
        return try #require(Self.texts(result).first)
    }

    /// Het hele antwoord als JSON, zoals het over de draad gaat.
    func wire(_ name: String, _ arguments: [String: Value] = [:]) async throws -> String {
        let result = try await call(name, arguments)
        return String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
    }

    static func texts(_ result: CallTool.Result) -> [String] {
        result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { text } else { nil }
        }
    }
}

extension Value {
    subscript(key: String) -> Value? {
        objectValue?[key]
    }

    /// De objecten van een lijst.
    var objects: [[String: Value]] {
        arrayValue?.compactMap(\.objectValue) ?? []
    }
}
