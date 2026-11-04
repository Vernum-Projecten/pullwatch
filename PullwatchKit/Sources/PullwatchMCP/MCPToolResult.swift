import Foundation
public import MCP

/// Wat een tool teruggeeft: gestructureerde inhoud (een JSON-object volgens het uitvoerschema)
/// en een korte samenvatting voor het model.
public struct MCPToolResult: Sendable, Hashable {
    /// Het JSON-object, als `structuredContent` van het antwoord.
    public let structuredContent: [String: Value]
    /// Een korte samenvatting in het Engels ("3 open pull requests, 1 with failing checks.").
    public let summary: String

    public init(structuredContent: [String: Value], summary: String) {
        self.structuredContent = structuredContent
        self.summary = summary
    }

    /// Codeert `output` als JSON-object; datums als ISO 8601 (`date-time`).
    public init(encoding output: some Encodable, summary: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let value = try JSONDecoder().decode(Value.self, from: encoder.encode(output))
        guard case let .object(fields) = value else {
            throw MCPError.internalError("Tool output must encode as a JSON object")
        }
        self.init(structuredContent: fields, summary: summary)
    }

    /// Het antwoord op `tools/call`. Na de samenvatting staat dezelfde JSON nog eens als tekst,
    /// zoals de specificatie aanraadt voor clients die `structuredContent` niet lezen.
    var callResult: CallTool.Result {
        let structured: Value? = .object(structuredContent)
        var content: [Tool.Content] = [.text(text: summary, annotations: nil, _meta: nil)]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(structured), let json = String(data: data, encoding: .utf8) {
            content.append(.text(text: json, annotations: nil, _meta: nil))
        }
        return CallTool.Result(content: content, structuredContent: structured, isError: false)
    }
}
