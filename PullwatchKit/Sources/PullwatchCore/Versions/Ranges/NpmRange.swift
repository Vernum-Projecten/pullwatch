import Foundation

/// node-semver-bereiken zoals in package.json, yarn.lock en pnpm-lock.yaml
/// (https://github.com/npm/node-semver#ranges): `||`, spatie als en, `1.2.3 - 2.3.4`, x-bereiken
/// (`1.x`, `1.2.*`, `1`), `~`, `^` en `<`, `<=`, `>`, `>=`, `=`. Een pre-release valt alleen in het
/// bereik als een voorwaarde in hetzelfde alternatief een pre-release met hetzelfde
/// major.minor.patch noemt. Geen bereik: tags (`latest`), paden, URL's, git en `workspace:`.
enum NpmRange {
    static func parse(_ text: String) -> VersionRange? {
        var spec = text.trimmingCharacters(in: .whitespaces)
        // Alias: "npm:string-width@^4.2.0" is het bereik van string-width; Berry schrijft ook
        // "npm:^4.2.0" (een bereik zonder naam). "npm:lodash" zonder bereik is geen bereik.
        if spec.hasPrefix("npm:") {
            let rest = String(spec.dropFirst(4))
            let target = DependencyDetector.descriptorName(rest)
            spec = target.range.isEmpty ? rest : target.range
        }
        guard !spec.contains(":"), !spec.contains("/") else { return nil }
        var alternatives: [[VersionRange.Comparator]] = []
        for part in spec.components(separatedBy: "||") {
            guard let set = comparators(part) else { return nil }
            alternatives.append(set)
        }
        return VersionRange(alternatives, prereleases: .sameRelease)
    }

    private static func comparators(_ text: String) -> [VersionRange.Comparator]? {
        let part = text.trimmingCharacters(in: .whitespaces)
        if part.isEmpty { return [] }
        if let (from, to) = VersionRange.hyphen(part) {
            guard let lower = PartialVersion(from), let upper = PartialVersion(to) else { return nil }
            var set = lower.known.isEmpty ? [] : [VersionRange.Comparator(.greaterOrEqual, lower.lower)]
            if upper.isComplete {
                set.append(VersionRange.Comparator(.lessOrEqual, upper.lower))
            } else if let next = upper.nextAfterKnown {
                set.append(VersionRange.Comparator(.belowRelease, next))
            }
            return set
        }
        var set: [VersionRange.Comparator] = []
        for token in VersionRange.joiningOperators(part).split(whereSeparator: \.isWhitespace) {
            let (op, rest) = VersionRange.splitOperator(String(token), ["^", "~>", "~", ">=", "<=", ">", "<", "="])
            guard let partial = PartialVersion(rest) else { return nil }
            switch op {
            case "^": set += VersionRange.caret(partial)
            case "~", "~>": set += VersionRange.tilde(partial)
            default:
                guard let found = VersionRange.primitive(op, partial) else { return nil }
                set += found
            }
        }
        return set
    }
}
