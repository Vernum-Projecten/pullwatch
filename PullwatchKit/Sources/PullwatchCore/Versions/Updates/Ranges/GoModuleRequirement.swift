import Foundation

/// Een `require` in go.mod (https://go.dev/ref/mod#versions en #major-version-suffixes): een
/// exacte minimumversie; Go kiest de hoogste die een module vraagt. Een nieuwe major is een ander
/// modulepad (`example.com/mod/v2`, `gopkg.in/yaml.v3`), dus andere imports: binnen het bereik
/// valt alleen dezelfde major (v0 en v1 delen het pad zonder achtervoegsel). Een
/// `+incompatible`-versie (v2 of hoger zonder go.mod) heeft geen achtervoegsel en dus geen grens.
///
/// In Go is go.mod ook de lockfile: "binnen bereik" betekent hier `go get` zonder imports te
/// veranderen.
enum GoModuleRequirement {
    static func parse(module: String, version text: String) -> VersionRange? {
        guard let version = Version(text) else { return nil }
        let lower = VersionRange.Comparator(.greaterOrEqual, version)
        if version.local == "incompatible" { return VersionRange([[lower]]) }
        let major: Int
        if let suffix = module.firstMatch(of: /\/v(\d+)$/) ?? module.firstMatch(of: /^gopkg\.in\/.+\.v(\d+)$/),
           let value = Int(suffix.output.1) {
            major = value
        } else if version.part(0) <= 1 {
            major = 1
        } else {
            // v2+ zonder achtervoegsel en zonder +incompatible: ongeldig in Go, dus geen grens.
            return VersionRange([[lower]])
        }
        return VersionRange([[lower, VersionRange.Comparator(.belowRelease, Version(release: [major + 1, 0, 0]))]])
    }
}
