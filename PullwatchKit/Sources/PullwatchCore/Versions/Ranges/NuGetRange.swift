import Foundation

/// NuGet-versiebereiken (https://learn.microsoft.com/nuget/concepts/package-versioning#version-ranges):
/// een kale versie is een minimum (`1.0` is ≥ 1.0), verder intervallen met `[` en `]` (inclusief)
/// en `(` en `)` (exclusief): `[1.0]`, `[1.0,2.0)`, `(,1.0]`, `(1.0,)`. Zwevende versies (`1.*`,
/// `1.0.*`, `*`) zijn het bereik waarbinnen NuGet de hoogste kiest; `1.0.0-*` laat ook
/// pre-releases toe. MSBuild-eigenschappen (`$(Version)`) zijn geen bereik.
enum NuGetRange {
    static func parse(_ text: String) -> VersionRange? {
        let spec = text.filter { !$0.isWhitespace }
        guard !spec.isEmpty, !spec.contains("$") else { return nil }
        guard let open = spec.first, open == "[" || open == "(" else { return floating(spec) }
        guard let close = spec.last, close == "]" || close == ")", spec.count >= 2 else { return nil }
        let inner = spec.dropFirst().dropLast()
        let bounds = inner.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        if bounds.count == 1 {
            // "[1.0]" is precies 1.0; "(1.0)" bestaat niet.
            guard open == "[", close == "]", let exact = Version(bounds[0]) else { return nil }
            return VersionRange([[VersionRange.Comparator(.equal, exact)]])
        }
        guard bounds.count == 2 else { return nil }
        var set: [VersionRange.Comparator] = []
        if !bounds[0].isEmpty {
            guard let lower = PartialVersion(bounds[0]) else { return nil }
            set.append(VersionRange.Comparator(open == "[" ? .greaterOrEqual : .greater, lower.lower))
        }
        if !bounds[1].isEmpty {
            guard let upper = Version(bounds[1]) else { return nil }
            set.append(VersionRange.Comparator(close == "]" ? .lessOrEqual : .less, upper))
        }
        return VersionRange([set], allowsPrereleases: bounds[0].hasSuffix("-*"))
    }

    /// Kaal: een minimum, of met `*` zwevend binnen de geschreven delen.
    private static func floating(_ spec: String) -> VersionRange? {
        let prereleases = spec.hasSuffix("-*")
        let base = prereleases ? String(spec.dropLast(2)) : spec
        if base == "*" { return VersionRange([[]], allowsPrereleases: prereleases) }
        guard let partial = PartialVersion(base, wildcards: ["*"]) else { return nil }
        if partial.parts.contains(nil) {
            return VersionRange([VersionRange.wildcard(partial)], allowsPrereleases: prereleases)
        }
        guard partial.prerelease.isEmpty || !prereleases else { return nil }
        let lower = prereleases ? Version(release: partial.known, prerelease: ["0"]) : partial.lower
        return VersionRange([[VersionRange.Comparator(.greaterOrEqual, lower)]], allowsPrereleases: prereleases)
    }
}
