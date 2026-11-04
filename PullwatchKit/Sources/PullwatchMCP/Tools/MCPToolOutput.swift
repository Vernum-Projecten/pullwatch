import Foundation
import MCP

/// Maakt van een `Encodable` uitvoerwaarde het resultaat van een tool: velden in snake_case,
/// datums als ISO 8601. Uitvoertypen gebruiken geen woordenboeken met eigen sleutels, want de
/// sleutelstrategie zou die ook omzetten.
enum MCPToolOutput {
    static func result(_ output: some Encodable, summary: String) throws -> MCPToolResult {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let value = try JSONDecoder().decode(Value.self, from: encoder.encode(output))
        guard case let .object(fields) = value else {
            throw MCPError.internalError("Tool output must encode as a JSON object")
        }
        return MCPToolResult(structuredContent: fields, summary: summary)
    }

    /// "1 pull request", "3 pull requests".
    static func count(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(count) \(count == 1 ? singular : plural ?? singular + "s")"
    }
}

extension MCPSchema {
    /// Een datum en tijd in ISO 8601.
    static func dateTime(_ description: String) -> MCPSchema {
        .string(description, format: "date-time")
    }
}
