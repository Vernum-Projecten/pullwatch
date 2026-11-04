import Foundation

/// De requirement van een `.package(url:…)` in Package.swift
/// (https://developer.apple.com/documentation/packagedescription/package/dependency): `from: "1.2.3"`
/// en `.upToNextMajor(from:)` (tot 2.0.0), `.upToNextMinor(from:)` (tot 1.3.0), `exact:` en
/// `.exact(_:)`, en een bereik `"1.2.3"..<"2.0.0"` of `"1.2.3"..."1.4.0"`. `branch:` en
/// `revision:` zijn geen bereik. Pre-releases alleen als een grens er een is.
enum SwiftRequirement {
    static func parse(_ text: String) -> VersionRange? {
        let spec = text.trimmingCharacters(in: .whitespaces)
        if let m = spec.wholeMatch(of: /"([^"]+)"\s*(\.\.<|\.\.\.)\s*"([^"]+)"/) {
            guard let lower = Version(String(m.output.1)), let upper = Version(String(m.output.3)) else { return nil }
            return VersionRange([[VersionRange.Comparator(.greaterOrEqual, lower),
                                  VersionRange.Comparator(m.output.2 == "..<" ? .less : .lessOrEqual, upper)]])
        }
        guard let m = spec.wholeMatch(of: /\.?(from|upToNextMajor|upToNextMinor|exact)\s*(?:\(\s*(?:from\s*:)?|:)\s*"([^"]+)"\s*\)?/),
              let version = Version(String(m.output.2)) else { return nil }
        let lower = VersionRange.Comparator(.greaterOrEqual, version)
        switch m.output.1 {
        case "exact":
            return VersionRange([[VersionRange.Comparator(.equal, version)]])
        case "upToNextMinor":
            return VersionRange([[lower, VersionRange.Comparator(.less, Version(release: [version.part(0), version.part(1) + 1, 0]))]])
        default:
            return VersionRange([[lower, VersionRange.Comparator(.less, Version(release: [version.part(0) + 1, 0, 0]))]])
        }
    }
}
