import Foundation

/// Composer-constraints uit composer.json en de `require` van composer.lock
/// (https://getcomposer.org/doc/articles/versions.md): `||` (of `|`) als of, spatie of komma als
/// en, `1.0 - 2.0`, `1.0.*`, `~1.2` (tot 2.0), `~1.2.3` (tot 1.3.0), `^1.2.3`, `>`, `>=`, `<`,
/// `<=`, `!=`, en een exacte versie (`1.0` is precies 1.0.0). Stabiliteitsvlaggen (`@dev`, `@beta`)
/// en een pre-release in de constraint laten pre-releases toe. Branches (`dev-main`) zijn geen bereik.
enum ComposerConstraint {
    static func parse(_ text: String) -> VersionRange? {
        var spec = text.trimmingCharacters(in: .whitespaces)
        // Inline alias "1.0.x-dev as 1.0.0": wat geïnstalleerd wordt is het eerste deel.
        if let alias = spec.range(of: " as ") { spec = String(spec[..<alias.lowerBound]) }
        spec = spec.replacing(/#\S*/, with: "")
        var allowsPrereleases = false
        if spec.firstMatch(of: /@(?i:dev|alpha|beta|rc)\b/) != nil { allowsPrereleases = true }
        spec = spec.replacing(/@(?i:dev|alpha|beta|rc|stable)\b/, with: "")
        guard !spec.contains("dev-") else { return nil }
        var alternatives: [[VersionRange.Comparator]] = []
        for part in spec.split(separator: /\s*\|\|?\s*/) {
            guard let set = comparators(String(part)) else { return nil }
            alternatives.append(set)
        }
        if alternatives.isEmpty { alternatives = [[]] }
        return VersionRange(alternatives, prereleases: .whenNamed, allowsPrereleases: allowsPrereleases)
    }

    private static func comparators(_ text: String) -> [VersionRange.Comparator]? {
        if let (from, to) = VersionRange.hyphen(text) {
            // "1.0 - 2.0" is >=1.0.0 <2.1: een deels geschreven bovengrens telt als joker.
            guard let lower = PartialVersion(from), let upper = PartialVersion(to) else { return nil }
            let top: [VersionRange.Comparator] = if upper.isComplete {
                [VersionRange.Comparator(.lessOrEqual, upper.lower)]
            } else {
                upper.nextAfterKnown.map { [VersionRange.Comparator(.belowRelease, $0)] } ?? []
            }
            return [VersionRange.Comparator(.greaterOrEqual, lower.lower)] + top
        }
        var set: [VersionRange.Comparator] = []
        for token in VersionRange.joiningOperators(text).split(whereSeparator: { $0.isWhitespace || $0 == "," }) {
            let (op, rest) = VersionRange.splitOperator(String(token), ["^", "~", ">=", "<=", "!=", "<>", ">", "<", "==", "="])
            guard let partial = PartialVersion(rest) else { return nil }
            switch op {
            case "^":
                set += VersionRange.caret(partial)
            case "~":
                // Het een-na-laatste geschreven deel gaat omhoog; met één deel het eerste.
                set.append(VersionRange.Comparator(.greaterOrEqual, partial.lower))
                if let upper = partial.bumped(at: max(partial.known.count - 2, 0)) {
                    set.append(VersionRange.Comparator(.belowRelease, upper))
                }
            case _ where partial.parts.contains(nil):
                set += VersionRange.wildcard(partial)
            case ">=": set.append(VersionRange.Comparator(.greaterOrEqual, partial.lower))
            case "<=": set.append(VersionRange.Comparator(.lessOrEqual, partial.lower))
            case ">": set.append(VersionRange.Comparator(.greater, partial.lower))
            case "<": set.append(VersionRange.Comparator(.belowRelease, partial.lower))
            case "!=", "<>": set.append(VersionRange.Comparator(.notEqual, partial.lower))
            default: set.append(VersionRange.Comparator(.equal, partial.lower))
            }
        }
        return set
    }
}
