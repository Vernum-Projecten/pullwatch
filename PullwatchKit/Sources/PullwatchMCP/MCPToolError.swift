import MCP

/// Een fout die een tool aan het model laat zien, bijvoorbeeld "Repository acme/web is not
/// followed in Pullwatch." Het antwoord is dan een resultaat met `isError`, zodat het model zich
/// kan verbeteren; elke andere fout geeft alleen een algemene melding en komt in het log.
public struct MCPToolError: Error, Sendable, Hashable {
    /// De melding in het Engels, voor het model.
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    /// Het antwoord op `tools/call` met `message` als fout.
    static func callResult(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
    }
}
