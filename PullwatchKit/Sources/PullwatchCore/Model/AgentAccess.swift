import Foundation

/// Of coding agents Pullwatch via MCP mogen gebruiken (Instellingen, Agents), zoals Xcode het
/// voor zijn eigen tools regelt. De app leest het om de socket te openen; de helper
/// `pullwatch-mcp` leest het uit config.json om te weten wat hij een agent antwoordt.
public enum AgentAccess: String, Codable, CaseIterable, Sendable {
    /// Geen enkele agent: de app opent geen socket en de helper weigert elk verzoek.
    case never
    /// Alleen zolang Pullwatch draait; anders zegt de helper dat Pullwatch open moet.
    case whileOpen
    /// Ook als Pullwatch niet draait: de helper start Pullwatch op de achtergrond.
    case always

    /// Een onbekende waarde (van een nieuwere versie, of met de hand gewijzigd) is `never`: bij
    /// twijfel krijgt geen agent toegang.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AgentAccess(rawValue: raw) ?? .never
    }

    /// Of de app de socket open hoort te hebben.
    public var opensSocket: Bool { self != .never }
}
