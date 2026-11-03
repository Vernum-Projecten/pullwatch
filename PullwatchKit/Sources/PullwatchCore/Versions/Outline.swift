import Foundation

/// Een ingesprongen bestand als boom: het deel van YAML dat pnpm-lock.yaml en yarn Berry gebruiken
/// (`sleutel: waarde`, `sleutel:` met een blok eronder, sleutels tussen quotes) en de vorm van
/// yarn.lock v1 (`sleutel "waarde"`, zonder dubbele punt). Geen YAML-bibliotheek: geen ankers, geen
/// blokscalars, flow-waarden (`{integrity: …}`, `[x64]`) blijven één ruwe string.
struct Outline: Sendable, Equatable {
    /// De sleutel zoals hij in het bestand staat, quotes inbegrepen (yarn v1 zet meerdere
    /// descriptors tussen quotes op één regel).
    var rawKey: String
    /// De waarde zonder quotes; nil voor een sleutel met een blok eronder.
    var value: String?
    var children: [Outline] = []

    /// De sleutel zonder quotes als hij één string tussen quotes is.
    var key: String { Outline.unquoted(rawKey) }

    subscript(_ key: String) -> Outline? {
        children.first { $0.key == key }
    }

    static func parse(_ content: String) -> [Outline] {
        var lines: [(indent: Int, key: String, value: String?)] = []
        for raw in content.split(whereSeparator: \.isNewline) {
            let text = raw.trimmingCharacters(in: .whitespaces)
            if text.isEmpty || text.hasPrefix("#") { continue }
            let (key, value) = split(text)
            lines.append((raw.prefix { $0 == " " }.count, key, value))
        }
        var index = 0
        func build(deeperThan parent: Int) -> [Outline] {
            var nodes: [Outline] = []
            while index < lines.count, lines[index].indent > parent {
                let line = lines[index]
                index += 1
                nodes.append(Outline(rawKey: line.key, value: line.value, children: build(deeperThan: line.indent)))
            }
            return nodes
        }
        return build(deeperThan: -1)
    }

    /// Eén regel in sleutel en waarde: `a: b` (YAML), `a "b"` (yarn v1), `a:` (blok erna) of
    /// `- x` (lijstitem, sleutel "-").
    static func split(_ text: String) -> (key: String, value: String?) {
        if text == "-" || text.hasPrefix("- ") {
            return ("-", unquoted(text.dropFirst().trimmingCharacters(in: .whitespaces)))
        }
        if text.hasSuffix(":") { return (String(text.dropLast()), nil) }
        if let quote = text.first, quote == "\"" || quote == "'" {
            var index = text.index(after: text.startIndex)
            while index < text.endIndex {
                if text[index] == quote {
                    // In YAML is '' binnen enkele quotes een quote.
                    let next = text.index(after: index)
                    if quote == "'", next < text.endIndex, text[next] == "'" {
                        index = text.index(after: next)
                        continue
                    }
                    break
                }
                if quote == "\"", text[index] == "\\" { index = text.index(after: index) }
                if index < text.endIndex { index = text.index(after: index) }
            }
            guard index < text.endIndex else { return (text, "") }
            let end = text.index(after: index)
            var rest = text[end...].trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix(":") { rest = rest.dropFirst().trimmingCharacters(in: .whitespaces) }
            return (String(text[..<end]), unquoted(rest))
        }
        let colon = text.range(of: ": ")
        let space = text.firstIndex(of: " ")
        if let colon, let space, text.index(after: colon.lowerBound) == space {
            return (String(text[..<colon.lowerBound]), unquoted(text[colon.upperBound...].trimmingCharacters(in: .whitespaces)))
        }
        if let space {
            return (String(text[..<space]), unquoted(text[space...].trimmingCharacters(in: .whitespaces)))
        }
        return (text, "")
    }

    /// `"x"` of `'x'` → x; iets anders (ook `"a", "b"`) blijft zoals het is.
    static func unquoted(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, first == "\"" || first == "'", text.last == first else { return text }
        let inner = String(text.dropFirst().dropLast())
        if first == "'" {
            guard !inner.replacingOccurrences(of: "''", with: "").contains("'") else { return text }
            return inner.replacingOccurrences(of: "''", with: "'")
        }
        guard !inner.replacingOccurrences(of: "\\\"", with: "").contains("\"") else { return text }
        return inner.replacingOccurrences(of: "\\\"", with: "\"")
    }
}
