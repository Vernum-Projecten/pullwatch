import Foundation

/// Version specifiers van PEP 440 (https://packaging.python.org/en/latest/specifications/version-specifiers/):
/// komma als en, `~=` (compatibel: `~= 2.2` is `>= 2.2, == 2.*`), `==` en `!=` met of zonder `.*`,
/// `<=`, `>=`, `<` (geen pre-release van de grens), `>` (geen post-release van de grens) en `===`.
/// Pre-releases alleen als een specifier er zelf een noemt.
///
/// Poetry schrijft in pyproject.toml ook `^1.2`, `~1.2`, `1.*`, `*`, `||` en een kale versie
/// (precies die versie); die leest deze parser met de regels van Poetry
/// (https://python-poetry.org/docs/dependency-specification/), gelijk aan die van Cargo.
enum PEP440Specifier {
    static func parse(_ text: String) -> VersionRange? {
        var alternatives: [[VersionRange.Comparator]] = []
        for part in text.components(separatedBy: "||") {
            var set: [VersionRange.Comparator] = []
            let items = part.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            for item in items where !(item.isEmpty && items.count == 1) {
                guard let found = comparators(item) else { return nil }
                set += found
            }
            alternatives.append(set)
        }
        return VersionRange(alternatives, prereleases: .whenNamed)
    }

    private static func version(_ text: String) -> Version? {
        Version(text, implicitPostRelease: true)
    }

    private static func comparators(_ item: String) -> [VersionRange.Comparator]? {
        let (op, rest) = VersionRange.splitOperator(item, ["~=", "===", "==", "!=", "<=", ">=", "<", ">", "^", "~"])
        guard !rest.isEmpty, !rest.contains(where: \.isWhitespace) else { return nil }
        switch op {
        case "===":
            return version(rest).map { [VersionRange.Comparator(.identical, $0)] }
        case "~=":
            // Minstens twee releasedelen; het laatste mag omhoog.
            guard let v = version(rest), v.release.count >= 2 else { return nil }
            return [VersionRange.Comparator(.greaterOrEqual, v),
                    VersionRange.Comparator(.prefix, Version(release: Array(v.release.dropLast())))]
        case "==", "!=":
            if rest.hasSuffix(".*") {
                guard let v = version(String(rest.dropLast(2))) else { return nil }
                return [VersionRange.Comparator(op == "==" ? .prefix : .notPrefix, Version(release: v.release))]
            }
            return version(rest).map { [VersionRange.Comparator(op == "==" ? .equal : .notEqual, $0)] }
        case "<=": return version(rest).map { [VersionRange.Comparator(.lessOrEqual, $0)] }
        case ">=": return version(rest).map { [VersionRange.Comparator(.greaterOrEqual, $0)] }
        case "<": return version(rest).map { [VersionRange.Comparator(.exclusiveLess, $0)] }
        case ">": return version(rest).map { [VersionRange.Comparator(.exclusiveGreater, $0)] }
        case "^": return PartialVersion(rest).map(VersionRange.caret)
        case "~": return PartialVersion(rest).map(VersionRange.tilde)
        default:
            // Poetry: "*", "1.*" en een kale versie.
            if rest == "*" { return [] }
            if rest.hasSuffix(".*") { return PartialVersion(rest).map(VersionRange.wildcard) }
            return version(rest).map { [VersionRange.Comparator(.equal, $0)] }
        }
    }
}
