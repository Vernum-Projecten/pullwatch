import MCP

/// Bouwt de MCP-server van Pullwatch: een `Server` van de SDK met Pullwatch als naam, alleen de
/// capability tools, en `tools/list` en `tools/call` uit een `MCPToolRegistry`. De SDK doet
/// JSON-RPC, de handshake en de versieonderhandeling; deze laag voegt alleen de tools en de
/// grenzen toe. Eén server per verbinding: de SDK houdt per server één sessie bij.
public enum PullwatchMCPServer {
    /// De naam in `serverInfo`, die de agent toont.
    public static let name = "Pullwatch"

    /// De MCP-protocolversies die de SDK spreekt; een client die een andere vraagt krijgt de
    /// nieuwste hiervan.
    public static var protocolVersions: Set<String> { Version.supported }

    /// Bouwt een server en start hem op `transport`, ingepakt in `MCPBoundedTransport`. Eén
    /// server per verbinding. `onInitialize` hoort welke client zich meldt (`clientInfo`, alleen
    /// om te tonen, geen beveiliging) en kan de sessie weigeren door te gooien. Met `approval`
    /// krijgt een client die nog niet is toegestaan op elke `tools/call` een toolfout die zegt
    /// waar hij kan worden toegestaan. `onToolCall` hoort elke toegestane `tools/call` met de
    /// naam van de tool.
    public static func start(
        tools: MCPToolRegistry,
        version: String,
        instructions: String? = nil,
        limits: MCPLimits = .standard,
        approval: MCPApproval? = nil,
        on transport: any Transport,
        onInitialize: (@Sendable (Client.Info) async throws -> Void)? = nil,
        onToolCall: (@Sendable (String) async -> Void)? = nil
    ) async throws -> Server {
        let handshake = Handshake()
        let server = Server(
            name: name,
            version: version,
            title: name,
            instructions: instructions,
            capabilities: Server.Capabilities(tools: .init(listChanged: false)),
            // Niet `.strict`: die weigert een verzoek voor `initialize` door te gooien in een taak
            // die de fout weggooit (SDK 0.12.1), zodat de client nooit antwoord krijgt. `Handshake`
            // doet die controle hier, met een echt foutantwoord.
            configuration: .default
        )
        await server.withMethodHandler(ListTools.self) { _ in
            try await handshake.requireDone()
            return ListTools.Result(tools: tools.definitions)
        }
        await server.withMethodHandler(LenientCallTool.self) { parameters in
            try await handshake.requireDone()
            let (name, arguments) = try LenientCallTool.parse(parameters)
            if let approval, let client = await handshake.client, !(await approval.isApproved(client.name)) {
                let displayName = MCPClientName.displayName(name: client.name, title: client.title)
                return MCPToolError.callResult(MCPApproval.waitingMessage(for: displayName))
            }
            await onToolCall?(name)
            return try await tools.call(name, arguments: arguments)
        }
        try await server.start(transport: MCPBoundedTransport(wrapping: transport, limits: limits)) { info, _ in
            try await onInitialize?(info)
            await handshake.markDone(info)
        }
        return server
    }
}

/// Of de client `initialize` al heeft gestuurd. Tot dan beantwoordt de server alleen `initialize`
/// en `ping`, zoals de specificatie vraagt.
private actor Handshake {
    /// De client uit `initialize`; nil tot de handshake.
    private(set) var client: Client.Info?

    func markDone(_ client: Client.Info) {
        self.client = client
    }

    func requireDone() throws(MCPError) {
        guard client != nil else { throw MCPError.invalidRequest("Server is not initialized; send initialize first") }
    }
}

/// `tools/call` met de parameters als losse JSON-waarde. Met het `CallTool` van de SDK zou een
/// aanroep zonder `name` of met `arguments` als tekst al bij het decoderen falen, en de SDK
/// maakt van zo'n decodeerfout `-32603` (internal error); de specificatie vraagt `-32602`
/// (invalid params). Hier leest Pullwatch de parameters zelf; het antwoord is dat van de SDK.
enum LenientCallTool: Method {
    static let name = CallTool.name
    typealias Parameters = Value
    typealias Result = CallTool.Result

    /// De toolnaam en argumenten, of `invalidParams` als de parameters niet die vorm hebben.
    static func parse(_ parameters: Value) throws(MCPError) -> (name: String, arguments: [String: Value]?) {
        guard case let .object(fields) = parameters else {
            throw MCPError.invalidParams("tools/call needs params with a tool name")
        }
        guard let name = fields["name"]?.textValue else {
            throw MCPError.invalidParams("tools/call needs `name`, the tool to call, as a string")
        }
        switch fields["arguments"] {
        case nil, .null:
            return (name, nil)
        case let .object(arguments):
            return (name, arguments)
        default:
            throw MCPError.invalidParams("`arguments` must be an object")
        }
    }
}
