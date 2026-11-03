import Foundation

/// Versie-eisen uit Cargo.toml (https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html):
/// zonder operator een caret (`"1.2"` is `^1.2`), verder `~`, `*` en `1.*`, `=`, `>`, `>=`, `<`,
/// `<=`, en meerdere eisen met een komma (`">= 1.2, < 1.5"`). Pre-releases zoals node-semver:
/// alleen als een eis een pre-release met hetzelfde major.minor.patch noemt.
enum CargoRequirement {
    static func parse(_ text: String) -> VersionRange? {
        var set: [VersionRange.Comparator] = []
        let items = text.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard !items.contains("") else { return nil }
        for item in items {
            let (op, rest) = VersionRange.splitOperator(item, ["^", "~", ">=", "<=", ">", "<", "="])
            guard let partial = PartialVersion(rest) else { return nil }
            switch op {
            case "^": set += VersionRange.caret(partial)
            case "~": set += VersionRange.tilde(partial)
            case "" where partial.parts.contains(nil): set += VersionRange.wildcard(partial)
            case "": set += VersionRange.caret(partial)
            default:
                guard let found = VersionRange.primitive(op, partial) else { return nil }
                set += found
            }
        }
        return VersionRange([set], prereleases: .sameRelease)
    }
}
