import Foundation

/// Een versiebereik uit een manifest of lockfile, voor elk ecosysteem in dezelfde vorm: een of
/// meer alternatieven (`||`), elk een rij voorwaarden die allemaal moeten gelden. De parsers per
/// ecosysteem (`NpmRange`, `ComposerConstraint`, `PEP440Specifier`, `CargoRequirement`,
/// `NuGetRange`, `GemRequirement`, `GoModuleRequirement`, `SwiftRequirement`) maken er een van.
struct VersionRange: Hashable, Sendable {
    struct Comparator: Hashable, Sendable {
        enum Operator: Hashable, Sendable {
            case equal, notEqual, less, lessOrEqual, greater, greaterOrEqual
            /// Releasedeel lager dan de grens, ook pre-releases van de grens uitgesloten: de
            /// bovengrens van `^1.2` (npm `<2.0.0-0`, RubyGems `~>`: `release < bump`).
            case belowRelease
            /// PEP 440 `== 1.4.*` en `!= 1.4.*`: het releasedeel begint met dat van de grens.
            case prefix, notPrefix
            /// PEP 440 `<V`: ook geen pre-release van V, tenzij V er zelf een is.
            case exclusiveLess
            /// PEP 440 `>V`: ook geen post-release van V, tenzij V er zelf een is.
            case exclusiveGreater
            /// PEP 440 `===`: dezelfde tekst.
            case identical
        }

        public let op: Operator
        public let version: Version

        public init(_ op: Operator, _ version: Version) {
            self.op = op
            self.version = version
        }

        public func matches(_ candidate: Version) -> Bool {
            switch op {
            case .equal: candidate == version
            case .notEqual: candidate != version
            case .less: candidate < version
            case .lessOrEqual: candidate <= version
            case .greater: candidate > version
            case .greaterOrEqual: candidate >= version
            case .belowRelease:
                candidate.epoch < version.epoch
                    || (candidate.epoch == version.epoch && Version.compare(candidate.release, version.release) == .orderedAscending)
            case .prefix: hasPrefix(candidate)
            case .notPrefix: !hasPrefix(candidate)
            case .exclusiveLess:
                candidate < version && (version.isPrerelease || !candidate.isPrerelease || !candidate.hasSameRelease(as: version))
            case .exclusiveGreater:
                candidate > version && (version.post != nil || candidate.post == nil || !candidate.hasSameRelease(as: version))
                    && candidate.local == nil
            case .identical: candidate.text.lowercased() == version.text.lowercased()
            }
        }

        /// PEP 440: de kandidaat wordt met nullen aangevuld tot de lengte van de grens.
        private func hasPrefix(_ candidate: Version) -> Bool {
            guard candidate.epoch == version.epoch else { return false }
            return version.release.indices.allSatisfy { candidate.part($0) == version.release[$0] }
        }
    }

    /// Wanneer een pre-release in het bereik mag vallen.
    enum Prereleases: Hashable, Sendable {
        /// node-semver en Cargo: alleen als een voorwaarde in hetzelfde alternatief een
        /// pre-release met hetzelfde major.minor.patch noemt.
        case sameRelease
        /// PEP 440, Composer, NuGet, RubyGems, SwiftPM: alleen als het bereik zelf een
        /// pre-release noemt (of, Composer, een stabiliteitsvlag als `@beta` heeft).
        case whenNamed
    }

    /// Of (`||`) van en (`,` of spatie); leeg betekent niets.
    let alternatives: [[Comparator]]
    let prereleases: Prereleases
    /// Het bereik staat pre-releases uitdrukkelijk toe (Composer `@dev`, NuGet `1.0.0-*`).
    let allowsPrereleases: Bool

    public init(_ alternatives: [[Comparator]], prereleases: Prereleases = .whenNamed, allowsPrereleases: Bool = false) {
        self.alternatives = alternatives
        self.prereleases = prereleases
        self.allowsPrereleases = allowsPrereleases
    }

    /// Elke versie (`*`).
    static func any(prereleases: Prereleases = .whenNamed) -> VersionRange {
        VersionRange([[]], prereleases: prereleases)
    }

    public func contains(_ version: Version) -> Bool {
        alternatives.contains { set in
            guard set.allSatisfy({ $0.matches(version) }) else { return false }
            guard version.isPrerelease, !allowsPrereleases else { return true }
            switch prereleases {
            case .sameRelease:
                return set.contains { $0.version.isPrerelease && $0.version.hasSameRelease(as: version) && $0.op != .belowRelease }
            case .whenNamed:
                return alternatives.joined().contains { $0.version.isPrerelease && $0.op != .belowRelease }
            }
        }
    }

    /// false voor tekst die geen versie is.
    public func contains(_ version: String) -> Bool {
        Version(version).map(contains) ?? false
    }

    /// Of `version` binnen het gevraagde bereik valt, zodat bijwerken alleen de lockfile verandert.
    func allowsUpdate(to version: String) -> Bool {
        contains(version)
    }

    /// Het bereik voor `requested` in `ecosystem` (de OSV-namen uit `Dependency.ecosystem`); nil als
    /// het geen versiebereik is (een branch, een pad, een tag als "latest") of het ecosysteem er
    /// geen kent. Go heeft de modulenaam nodig: de major staat in het pad.
    public static func parse(ecosystem: String, name: String, requested: String) -> VersionRange? {
        switch ecosystem {
        case "npm": NpmRange.parse(requested)
        case "Packagist": ComposerConstraint.parse(requested)
        case "PyPI": PEP440Specifier.parse(requested)
        case "crates.io": CargoRequirement.parse(requested)
        case "NuGet": NuGetRange.parse(requested)
        case "RubyGems": GemRequirement.parse(requested)
        case "Go": GoModuleRequirement.parse(module: name, version: requested)
        case "SwiftURL": SwiftRequirement.parse(requested)
        default: nil
        }
    }
}

/// Een deels geschreven versie (`1`, `1.2`, `1.x`, `1.2.*`): de ontbrekende of jokerdelen zijn nil.
/// Gedeeld door de parsers met caret-, tilde- en jokerbereiken.
struct PartialVersion {
    var parts: [Int?]
    var prerelease: String

    /// "1.2.x-beta" → [1, 2, nil], "beta". Een "v" of "=" vooraan valt weg. nil zonder getal of joker vooraan.
    init?(_ text: String, wildcards: Set<Character> = ["x", "X", "*"]) {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        while let first = rest.first, first == "v" || first == "V" || first == "=" { rest = rest.dropFirst() }
        if let plus = rest.firstIndex(of: "+") { rest = rest[..<plus] }
        var parts: [Int?] = []
        while parts.count < 4 {
            if let first = rest.first, wildcards.contains(first) {
                parts.append(nil)
                rest = rest.dropFirst()
            } else if let digits = rest.prefixMatch(of: /\d+/), let value = Int(digits.output) {
                parts.append(value)
                rest = rest[digits.range.upperBound...]
            } else {
                break
            }
            guard rest.first == "." else { break }
            rest = rest.dropFirst()
        }
        guard !parts.isEmpty else { return nil }
        // Na een joker telt niets meer: "1.x.3" is "1.x".
        if let wildcard = parts.firstIndex(of: nil) { parts = Array(parts[...wildcard]) }
        self.parts = parts
        self.prerelease = parts.contains(nil) ? "" : String(rest.drop { $0 == "-" || $0 == "." || $0 == "_" })
        if !prerelease.isEmpty, prerelease.contains(where: { $0.isWhitespace }) { return nil }
    }

    /// Delen die er echt staan, tot de eerste joker.
    var known: [Int] {
        parts.prefix { $0 != nil }.compactMap { $0 }
    }

    var isComplete: Bool { known.count >= 3 }

    /// De laagste versie die erbij past: ontbrekende delen 0, met de pre-release als die er is.
    var lower: Version {
        let release = known + Array(repeating: 0, count: max(0, 3 - known.count))
        guard !prerelease.isEmpty else { return Version(release: release) }
        return Version(release.map(String.init).joined(separator: ".") + "-" + prerelease) ?? Version(release: release)
    }

    /// De eerste versie boven de bekende delen: "1.2" → 1.3.0, "1" → 2.0.0; nil voor "*".
    var nextAfterKnown: Version? {
        bumped(at: known.count - 1)
    }

    /// Releasedeel met deel `index` één hoger en alles daarna 0.
    func bumped(at index: Int) -> Version? {
        guard index >= 0, index < known.count else { return nil }
        var release = Array(known.prefix(index + 1))
        release[index] += 1
        return Version(release: release + Array(repeating: 0, count: max(0, 3 - release.count)))
    }
}

extension VersionRange {
    /// "<= 1.2" → ("<=", "1.2"); de langste operator uit `operators` die vooraan staat, anders "".
    static func splitOperator(_ token: String, _ operators: [String]) -> (op: String, rest: String) {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        for op in operators.sorted(by: { $0.count > $1.count }) where trimmed.hasPrefix(op) {
            return (op, String(trimmed.dropFirst(op.count)).trimmingCharacters(in: .whitespaces))
        }
        return ("", trimmed)
    }

    /// Spaties tussen een operator en zijn versie weg (">= 1.2" → ">=1.2"), zodat een spatie
    /// daarna alleen nog voorwaarden scheidt.
    static func joiningOperators(_ text: String) -> String {
        text.replacing(/(===|==|!=|~=|~>|>=|<=|<>|\^|~|>|<|=)\s+/) { $0.output.1 }
    }

    /// "a - b" als hyphen-bereik; nil voor iets anders.
    static func hyphen(_ text: String) -> (from: String, to: String)? {
        text.trimmingCharacters(in: .whitespaces).wholeMatch(of: /(\S+)\s+-\s+(\S+)/).map { (String($0.output.1), String($0.output.2)) }
    }

    /// Caret zoals npm, Cargo en Poetry hem lezen: de eerste deel dat niet 0 is, blijft gelijk.
    /// `^1.2.3` → >=1.2.3 <2.0.0, `^0.2.3` → <0.3.0, `^0.0.3` → <0.0.4, `^0.0` → <0.1.0, `^0` → <1.0.0.
    static func caret(_ partial: PartialVersion) -> [Comparator] {
        let known = partial.known
        let lower = Comparator(.greaterOrEqual, partial.lower)
        guard !known.isEmpty else { return [] }
        // Alles 0: het laatste geschreven deel mag één omhoog ("^0.0.3" → <0.0.4, "^0.0" → <0.1.0).
        let index = known.firstIndex { $0 != 0 } ?? known.count - 1
        guard let upper = partial.bumped(at: index) else { return [lower] }
        return [lower, Comparator(.belowRelease, upper)]
    }

    /// Tilde zoals npm, Cargo en Poetry hem lezen: `~1.2.3` → >=1.2.3 <1.3.0, `~1.2` → <1.3.0, `~1` → <2.0.0.
    static func tilde(_ partial: PartialVersion) -> [Comparator] {
        let known = partial.known
        let lower = Comparator(.greaterOrEqual, partial.lower)
        guard let upper = partial.bumped(at: known.count >= 2 ? 1 : 0) else { return known.isEmpty ? [] : [lower] }
        return [lower, Comparator(.belowRelease, upper)]
    }

    /// Een jokerbereik of deels geschreven versie: "1.2.x" en "1.2" → >=1.2.0 <1.3.0; "*" → alles.
    static func wildcard(_ partial: PartialVersion) -> [Comparator] {
        guard let upper = partial.nextAfterKnown else { return [] }
        return [Comparator(.greaterOrEqual, partial.lower), Comparator(.belowRelease, upper)]
    }

    /// `op` met een deels geschreven versie, zoals node-semver en Cargo het lezen:
    /// `>1.2` → >=1.3.0, `<=1.2` → <1.3.0, `<1.2` → <1.2.0, `>=1.2` → >=1.2.0, `=1.2` → 1.2.x.
    static func primitive(_ op: String, _ partial: PartialVersion) -> [Comparator]? {
        guard !partial.known.isEmpty else {
            // "*" met ">=", "<=" of "=" is alles; ">*" en "<*" passen op niets.
            return [">=", "<=", "=", ""].contains(op) ? [] : nil
        }
        if partial.isComplete {
            switch op {
            case ">": return [Comparator(.greater, partial.lower)]
            case ">=": return [Comparator(.greaterOrEqual, partial.lower)]
            case "<": return [Comparator(.less, partial.lower)]
            case "<=": return [Comparator(.lessOrEqual, partial.lower)]
            case "=", "": return [Comparator(.equal, partial.lower)]
            default: return nil
            }
        }
        switch op {
        case ">": return partial.nextAfterKnown.map { [Comparator(.greaterOrEqual, $0)] }
        case ">=": return [Comparator(.greaterOrEqual, partial.lower)]
        case "<": return [Comparator(.belowRelease, partial.lower)]
        case "<=": return partial.nextAfterKnown.map { [Comparator(.belowRelease, $0)] }
        case "=", "": return wildcard(partial)
        default: return nil
        }
    }
}
