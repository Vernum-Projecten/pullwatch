import Foundation

/// Een coding agent waarvoor Instellingen, Agents de opdracht of JSON toont om Pullwatch toe te
/// voegen, met het pad van de helper in deze bundle. De vormen volgen de documentatie van elke
/// client: Claude Code (code.claude.com/docs/en/mcp), Codex
/// (developers.openai.com/codex/mcp), Cursor (cursor.com/docs/context/mcp) en VS Code
/// (code.visualstudio.com/docs/agents/reference/mcp-configuration).
nonisolated enum AgentClient: String, CaseIterable, Identifiable, Sendable {
    case claudeCode, codex, cursor, vsCode

    var id: Self { self }

    /// De naam van het product; niet vertaald.
    var name: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .vsCode: "VS Code"
        }
    }

    /// Waar de tekst heen moet.
    var placement: LocalizedStringResource {
        switch self {
        case .claudeCode, .codex: LocalizedStringResource("Voer uit in Terminal.", comment: "Instellingen, Agents: waar de opdracht voor een agent heen moet")
        case .cursor: LocalizedStringResource("Zet in ~/.cursor/mcp.json.", comment: "Instellingen, Agents: het configuratiebestand van Cursor")
        case .vsCode: LocalizedStringResource("Zet in .vscode/mcp.json van je project.", comment: "Instellingen, Agents: het configuratiebestand van VS Code")
        }
    }

    /// De opdracht of JSON met `helper` als pad van `pullwatch-mcp`.
    func setup(helper: String) -> String {
        switch self {
        case .claudeCode:
            "claude mcp add --transport stdio pullwatch -- \(Self.shellQuoted(helper))"
        case .codex:
            "codex mcp add pullwatch -- \(Self.shellQuoted(helper))"
        case .cursor:
            """
            {
              "mcpServers": {
                "pullwatch": {
                  "type": "stdio",
                  "command": \(Self.jsonQuoted(helper))
                }
              }
            }
            """
        case .vsCode:
            """
            {
              "servers": {
                "pullwatch": {
                  "type": "stdio",
                  "command": \(Self.jsonQuoted(helper))
                }
              }
            }
            """
        }
    }

    /// Het pad van de helper in de draaiende app.
    static var helperPath: String {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/pullwatch-mcp").path(percentEncoded: false)
    }

    // MARK: - Aanhalingstekens

    /// Een pad zoals een shell het als één woord leest: ongewijzigd als het alleen veilige tekens
    /// heeft, anders tussen enkele aanhalingstekens (een `'` erin wordt `'\''`).
    static func shellQuoted(_ text: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-+@%:,"))
        if !text.isEmpty, text.unicodeScalars.allSatisfy({ $0.isASCII && safe.contains($0) }) { return text }
        return "'" + text.replacing("'", with: #"'\''"#) + "'"
    }

    /// Tekst als JSON-string, met aanhalingstekens.
    static func jsonQuoted(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return (try? encoder.encode(text)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\(text)\""
    }
}
