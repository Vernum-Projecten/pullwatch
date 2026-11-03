import Foundation

/// RubyGems-requirements uit Gemfile en Gemfile.lock (https://guides.rubygems.org/patterns/#pessimistic-version-constraint
/// en `Gem::Requirement`): `=`, `!=`, `>`, `<`, `>=`, `<=` en `~>`, meerdere met een komma, allemaal
/// tegelijk. `~> 2.2` is >= 2.2 en < 3.0, `~> 2.2.0` is >= 2.2.0 en < 2.3; zoals `Gem::Version#bump`
/// tellen pre-releasedelen daarbij niet. Zonder operator is het `=`.
enum GemRequirement {
    static func parse(_ text: String) -> VersionRange? {
        var set: [VersionRange.Comparator] = []
        for item in text.split(separator: ",").map({ $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }) {
            let (op, rest) = VersionRange.splitOperator(item, ["~>", ">=", "<=", "!=", ">", "<", "="])
            guard !rest.contains(where: \.isWhitespace), let version = Version(rest) else { return nil }
            switch op {
            case "~>":
                // bump: het laatste releasedeel valt weg (als er meer dan één is), het deel ervoor gaat omhoog.
                var release = version.release
                if release.count > 1 { release.removeLast() }
                release[release.count - 1] += 1
                set += [VersionRange.Comparator(.greaterOrEqual, version), VersionRange.Comparator(.belowRelease, Version(release: release))]
            case ">=": set.append(VersionRange.Comparator(.greaterOrEqual, version))
            case "<=": set.append(VersionRange.Comparator(.lessOrEqual, version))
            case ">": set.append(VersionRange.Comparator(.greater, version))
            case "<": set.append(VersionRange.Comparator(.less, version))
            case "!=": set.append(VersionRange.Comparator(.notEqual, version))
            default: set.append(VersionRange.Comparator(.equal, version))
            }
        }
        return set.isEmpty ? nil : VersionRange([set])
    }
}
