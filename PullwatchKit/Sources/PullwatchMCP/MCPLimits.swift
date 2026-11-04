import Foundation

/// De grenzen aan wat een agent stuurt, zodat een te groot of te diep genest bericht een nette
/// fout geeft in plaats van geheugen of stack op te eten. Een transport dat van een stream leest
/// (de socket) buffert ook niet meer dan `maxMessageBytes` per bericht.
public struct MCPLimits: Sendable, Hashable {
    /// Het grootste bericht in bytes.
    public var maxMessageBytes: Int
    /// De diepste nesting van arrays en objecten in een bericht.
    public var maxDepth: Int

    public init(maxMessageBytes: Int, maxDepth: Int) {
        self.maxMessageBytes = maxMessageBytes
        self.maxDepth = maxDepth
    }

    /// Ruim voor elke vraag aan Pullwatch: de argumenten zijn een paar filters.
    public static let standard = MCPLimits(maxMessageBytes: 1 << 20, maxDepth: 32)

    // MARK: - Controleren

    /// Waarom `message` niet door mag, of nil als het past. Telt de nesting op de bytes, zonder
    /// het bericht te decoderen: haakjes binnen een tekst tellen niet mee.
    func violation(in message: Data) -> String? {
        if message.count > maxMessageBytes {
            return "Message is larger than \(maxMessageBytes) bytes"
        }
        var depth = 0
        var inString = false
        var escaped = false
        for byte in message {
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""):
                inString = true
            case UInt8(ascii: "["), UInt8(ascii: "{"):
                depth += 1
                if depth > maxDepth { return "Message is nested deeper than \(maxDepth) levels" }
            case UInt8(ascii: "]"), UInt8(ascii: "}"):
                depth -= 1
            default:
                break
            }
        }
        return nil
    }
}
