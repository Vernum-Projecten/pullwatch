public import MCP

/// Eén tool van de MCP-server: naam, beschrijving voor het model, invoer- en uitvoerschema en de
/// handler die het antwoord maakt. De handler krijgt alleen argumenten die al bij het
/// invoerschema passen, en zijn uitvoer wordt tegen het uitvoerschema gecontroleerd.
public struct MCPTool: Sendable {
    /// Maakt het antwoord. Gooi `MCPToolError` voor een fout die het model moet lezen
    /// ("not followed"), `MCPError` voor een protocolfout; elke andere fout wordt een algemene
    /// foutmelding.
    public typealias Handler = @Sendable (MCPArguments) async throws -> MCPToolResult

    /// De naam die de agent aanroept (`list_pull_requests`): 1 tot 128 tekens uit `A-Z a-z 0-9 _ - .`.
    public let name: String
    /// Een leesbare titel voor een client die tools toont.
    public let title: String?
    /// Wat de tool teruggeeft en wanneer het model hem gebruikt, in het Engels.
    public let description: String
    /// Het schema van de argumenten; altijd een object.
    public let inputSchema: MCPSchema
    /// Het schema van `structuredContent`; altijd een object.
    public let outputSchema: MCPSchema
    /// Hints voor de client; standaard alleen lezen, binnen Pullwatch.
    public let annotations: Tool.Annotations
    public let handler: Handler

    /// Een tool die alleen leest en alleen kent wat Pullwatch al heeft opgehaald.
    public static let readOnly = Tool.Annotations(readOnlyHint: true, idempotentHint: true, openWorldHint: false)

    public init(
        name: String,
        title: String? = nil,
        description: String,
        input: MCPSchema = .object([:]),
        output: MCPSchema,
        annotations: Tool.Annotations = MCPTool.readOnly,
        handler: @escaping Handler
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = input
        self.outputSchema = output
        self.annotations = annotations
        self.handler = handler
    }

    /// De tool zoals `tools/list` hem toont.
    public var definition: Tool {
        Tool(
            name: name,
            title: title,
            description: description,
            inputSchema: inputSchema.jsonSchema,
            annotations: annotations,
            outputSchema: outputSchema.jsonSchema
        )
    }
}
