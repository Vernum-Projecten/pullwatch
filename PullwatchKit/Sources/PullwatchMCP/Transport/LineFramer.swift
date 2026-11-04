package import Foundation

/// Knipt een bytestroom in regels, zoals de stdio-transport van MCP: elk JSON-RPC-bericht is één
/// regel, afgesloten met `\n`. Buffert nooit meer dan `maxLineBytes`: een langere regel wordt
/// gemeld zodra hij te lang wordt en de rest ervan tot de volgende `\n` overgeslagen. Zo kan een
/// agent het geheugen niet vullen met één eindeloze regel.
package struct LineFramer: Sendable {
    package enum Line: Sendable, Equatable {
        /// Een hele regel zonder de `\n` (en zonder een `\r` ervoor).
        case message(Data)
        /// Een regel langer dan `maxLineBytes`; hij is niet gelezen.
        case oversized
    }

    package let maxLineBytes: Int
    private var buffer = Data()
    /// Bezig de rest van een te lange regel over te slaan.
    private var skipping = false

    package init(maxLineBytes: Int) {
        self.maxLineBytes = maxLineBytes
    }

    /// De regels die met `chunk` af zijn.
    package mutating func append(_ chunk: Data) -> [Line] {
        var lines: [Line] = []
        var rest = chunk[...]
        while !rest.isEmpty {
            let newline = rest.firstIndex(of: UInt8(ascii: "\n"))
            let piece = rest[..<(newline ?? rest.endIndex)]
            rest = newline.map { rest[rest.index(after: $0)...] } ?? rest[rest.endIndex...]

            if skipping {
                if newline != nil { skipping = false }
                continue
            }
            if buffer.count + piece.count > maxLineBytes {
                lines.append(.oversized)
                buffer = Data()
                skipping = newline == nil
                continue
            }
            buffer.append(contentsOf: piece)
            if newline != nil, let line = takeLine() {
                lines.append(line)
            }
        }
        return lines
    }

    /// Wat er na het einde van de stroom nog staat: een laatste regel zonder `\n`.
    package mutating func finish() -> [Line] {
        defer { skipping = false }
        guard !skipping else { return [] }
        return takeLine().map { [$0] } ?? []
    }

    private mutating func takeLine() -> Line? {
        defer { buffer = Data() }
        var line = buffer
        if line.last == UInt8(ascii: "\r") { line.removeLast() }
        // Lege regels (een agent die een extra `\n` stuurt) zijn geen bericht.
        guard !line.isEmpty else { return nil }
        return .message(line)
    }
}
