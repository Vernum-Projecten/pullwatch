/// De naam van een agent zoals een persoon hem kent. `clientInfo.name` is vaak een technische
/// naam (`claude-code`); de `title` uit `initialize` gaat voor, dan de bekende clients, en
/// anders de naam zelf. Alleen om te tonen: toestaan gaat op `clientInfo.name`.
public enum MCPClientName {
    /// De namen die bekende clients in `clientInfo.name` sturen.
    static let known: [String: String] = [
        "claude-code": "Claude Code",
        "codex-mcp-client": "Codex",
        "cursor-vscode": "Cursor",
        "Visual Studio Code": "VS Code",
        "Visual Studio Code - Insiders": "VS Code Insiders",
    ]

    public static func displayName(name: String, title: String? = nil) -> String {
        if let title, !title.allSatisfy(\.isWhitespace) { return title }
        return known[name] ?? name
    }
}
