import Foundation
public import MCP
import PullwatchCore

/// De tools van de server, op naam. Beantwoordt `tools/list` en `tools/call`: controleert de
/// argumenten, roept de handler aan en vangt elke fout op, zodat slechte invoer of een falende
/// tool nooit de server laat vallen.
public struct MCPToolRegistry: Sendable {
    /// De tools in de volgorde waarin ze zijn opgegeven; zo toont `tools/list` ze ook.
    public let tools: [MCPTool]
    private let byName: [String: MCPTool]
    private let limits: MCPLimits
    private static let log = Log(category: "MCP")

    /// Weigert een lijst met een ongeldige of dubbele naam, of met een schema dat geen object is:
    /// dat is een fout in de code, en die hoort in een test op te vallen.
    public init(_ tools: [MCPTool], limits: MCPLimits = .standard) throws(InvalidTool) {
        var byName: [String: MCPTool] = [:]
        for tool in tools {
            guard Self.isValidName(tool.name) else { throw InvalidTool(name: tool.name, reason: "invalid name") }
            guard byName[tool.name] == nil else { throw InvalidTool(name: tool.name, reason: "duplicate name") }
            guard tool.inputSchema.isObject else { throw InvalidTool(name: tool.name, reason: "input schema is not an object") }
            guard tool.outputSchema.isObject else { throw InvalidTool(name: tool.name, reason: "output schema is not an object") }
            byName[tool.name] = tool
        }
        self.tools = tools
        self.byName = byName
        self.limits = limits
    }

    /// Waarom een tool niet in het register past.
    public struct InvalidTool: Error, Sendable, Hashable {
        public let name: String
        public let reason: String
    }

    /// 1 tot 128 tekens uit `A-Z a-z 0-9 _ - .`, zoals de specificatie (2025-11-25) vraagt.
    private static func isValidName(_ name: String) -> Bool {
        (1...128).contains(name.utf8.count)
            && name.utf8.allSatisfy { byte in
                switch byte {
                case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                    UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"), UInt8(ascii: "-"), UInt8(ascii: "."):
                    true
                default:
                    false
                }
            }
    }

    // MARK: - Aanroepen

    /// Het antwoord op `tools/list`.
    public var definitions: [Tool] {
        tools.map(\.definition)
    }

    /// Roept tool `name` aan. Een onbekende tool geeft `MCPError.invalidParams` (-32602), een
    /// protocolfout. Argumenten die niet bij het schema passen of te diep genest zijn geven, zoals
    /// MCP 2025-11-25 aanraadt, een resultaat met `isError` en een melding die het veld noemt,
    /// zodat het model de aanroep kan verbeteren; een fout in de tool ook.
    public func call(_ name: String, arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let tool = byName[name] else {
            throw MCPError.invalidParams("Unknown tool: \(name)")
        }
        let arguments = arguments ?? [:]
        let value = Value.object(arguments)
        guard value.isNested(within: limits.maxDepth) else {
            return MCPToolError.callResult("Invalid arguments for \(name): they are nested deeper than \(limits.maxDepth) levels.")
        }
        do {
            try tool.inputSchema.validate(value)
        } catch {
            return MCPToolError.callResult("Invalid arguments for \(name): \(error.message).")
        }

        let result: MCPToolResult
        do {
            result = try await tool.handler(MCPArguments(arguments))
        } catch let error as MCPToolError {
            return MCPToolError.callResult(error.message)
        } catch let error as MCPError {
            throw error
        } catch is CancellationError {
            // De client heeft de aanvraag ingetrokken; de SDK stuurt dan geen antwoord.
            throw CancellationError()
        } catch {
            Self.log.error("MCP-tool \(name) faalde: \(error)")
            return MCPToolError.callResult("The tool \(name) failed inside Pullwatch.")
        }

        do {
            try tool.outputSchema.validate(.object(result.structuredContent))
        } catch {
            Self.log.error("MCP-tool \(name) gaf uitvoer buiten zijn schema: \(error.message)")
            throw MCPError.internalError("The tool \(name) returned output that does not match its output schema")
        }
        return result.callResult
    }
}

extension Value {
    /// Of de waarde niet dieper dan `limit` arrays en objecten genest is; stopt bij de eerste die
    /// te diep gaat.
    func isNested(within limit: Int) -> Bool {
        switch self {
        case let .array(elements):
            limit > 0 && elements.allSatisfy { $0.isNested(within: limit - 1) }
        case let .object(fields):
            limit > 0 && fields.values.allSatisfy { $0.isNested(within: limit - 1) }
        default:
            true
        }
    }
}
