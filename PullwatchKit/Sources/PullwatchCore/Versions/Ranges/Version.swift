import Foundation

/// Een versienummer zoals de registers het schrijven, ruim gelezen: semver (npm, Cargo, NuGet,
/// Swift), PEP 440 (epoch, `a1`, `.post1`, `.dev1`), RubyGems (`1.0.0.beta1`), Composer (`-RC1`,
/// `-dev`) en Go (`v1.2.3+incompatible`). Vergelijken gaat op getallen met aangevulde nullen,
/// net als `VersionChecker.isOlder`: "8" is "8.0", "1.10" is nieuwer dan "1.9".
///
/// Volgorde bij hetzelfde releasedeel, zoals PEP 440 het voorschrijft en de andere ecosystemen
/// in de praktijk ook: `1.0.dev1` < `1.0a1` < `1.0rc1` < `1.0` < `1.0.post1`. Build-metadata en
/// lokale labels (`+incompatible`, `+ubuntu1`) tellen bij vergelijken niet mee.
public struct Version: Comparable, Hashable, Sendable, CustomStringConvertible {
    let epoch: Int
    public let release: [Int]
    /// Pre-release-delen (`["beta", "2"]`); leeg voor een release.
    public let prerelease: [String]
    /// Post-release (PEP 440 `.post1`, Composer `-patch1`); nil zonder.
    public let post: Int?
    /// Ontwikkelrelease (PEP 440 `.dev1`, Composer `-dev`); nil zonder.
    public let dev: Int?
    /// Alles na "+": build-metadata of een lokaal label.
    public let local: String?
    /// De tekst zoals gelezen.
    public let text: String

    /// nil zonder releasedeel ("latest", "dev-main", "*").
    /// - Parameter implicitPostRelease: PEP 440 leest `1.0-1` als `1.0.post1`; semver als pre-release.
    public init?(_ text: String, implicitPostRelease: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        var rest = Substring(trimmed.lowercased())
        if rest.first == "v" { rest = rest.dropFirst() }
        var local: String?
        if let plus = rest.firstIndex(of: "+") {
            local = String(rest[rest.index(after: plus)...])
            rest = rest[..<plus]
        }
        var epoch = 0
        if let match = rest.prefixMatch(of: /(\d+)!/) {
            guard let value = Int(match.output.1) else { return nil }
            epoch = value
            rest = rest[match.range.upperBound...]
        }
        guard let match = rest.prefixMatch(of: /\d+(?:\.\d+)*/) else { return nil }
        let release = match.output.split(separator: ".").compactMap { Int($0) }
        guard release.count == match.output.split(separator: ".").count else { return nil }
        let tail = rest[match.range.upperBound...]

        var post: Int?
        var dev: Int?
        var tokens = Version.tokens(tail)
        if implicitPostRelease, let m = tail.wholeMatch(of: /-(\d+)/) {
            post = Int(m.output.1)
            tokens = []
        }
        // Een "dev" aan het eind, eventueel met nummer, is een ontwikkelrelease.
        if let index = tokens.lastIndex(of: "dev"), index >= tokens.count - 2,
           tokens[(index + 1)...].allSatisfy({ Int($0) != nil }) {
            dev = tokens.count > index + 1 ? Int(tokens[index + 1]) : 0
            tokens.removeSubrange(index...)
        }
        // Daarvoor eventueel een post-release.
        if let index = tokens.lastIndex(where: Version.postWords.contains), index >= tokens.count - 2,
           tokens[(index + 1)...].allSatisfy({ Int($0) != nil }) {
            post = tokens.count > index + 1 ? Int(tokens[index + 1]) : 0
            tokens.removeSubrange(index...)
        }
        self.epoch = epoch
        self.release = release
        self.prerelease = tokens
        self.post = post
        self.dev = dev
        self.local = local
        self.text = trimmed
    }

    /// Een versie uit losse delen, voor grenzen die een parser zelf maakt (`<2.0.0`).
    init(release: [Int], prerelease: [String] = []) {
        self.epoch = 0
        self.release = release
        self.prerelease = prerelease
        self.post = nil
        self.dev = nil
        self.local = nil
        self.text = release.map(String.init).joined(separator: ".") + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
    }

    public var description: String { text }

    /// Pre-release of ontwikkelrelease: register en resolver kiezen die alleen als daarom gevraagd is.
    public var isPrerelease: Bool { !prerelease.isEmpty || dev != nil }

    /// Major, minor en patch, aangevuld met nullen.
    func part(_ index: Int) -> Int { index < release.count ? release[index] : 0 }

    /// Zelfde releasedeel, ongeacht pre-, post- en ontwikkelrelease: "1.2.3-beta" en "1.2.3".
    func hasSameRelease(as other: Version) -> Bool {
        epoch == other.epoch && Version.compare(release, other.release) == .orderedSame
    }

    // MARK: - Vergelijken

    public static func < (lhs: Version, rhs: Version) -> Bool { compare(lhs, rhs) == .orderedAscending }

    public static func == (lhs: Version, rhs: Version) -> Bool { compare(lhs, rhs) == .orderedSame }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(epoch)
        hasher.combine(Array(release.reversed().drop { $0 == 0 }.reversed()))
        hasher.combine(prerelease.map { Version.rank[$0].map(String.init) ?? $0 })
        hasher.combine(post)
        hasher.combine(dev)
    }

    static func compare(_ a: Version, _ b: Version) -> ComparisonResult {
        if a.epoch != b.epoch { return a.epoch < b.epoch ? .orderedAscending : .orderedDescending }
        let release = compare(a.release, b.release)
        if release != .orderedSame { return release }
        // PEP 440: alleen een ontwikkelrelease komt vóór alle pre-releases; zonder pre-release is
        // de release zelf nieuwer dan elke pre-release.
        let preA = a.prerelease.isEmpty ? (a.post == nil && a.dev != nil ? -1 : 1) : 0
        let preB = b.prerelease.isEmpty ? (b.post == nil && b.dev != nil ? -1 : 1) : 0
        if preA != preB { return preA < preB ? .orderedAscending : .orderedDescending }
        if preA == 0 {
            let pre = compare(prerelease: a.prerelease, b.prerelease)
            if pre != .orderedSame { return pre }
        }
        if a.post != b.post {
            guard let postA = a.post else { return .orderedAscending }
            guard let postB = b.post else { return .orderedDescending }
            return postA < postB ? .orderedAscending : .orderedDescending
        }
        if a.dev != b.dev {
            guard let devA = a.dev else { return .orderedDescending }
            guard let devB = b.dev else { return .orderedAscending }
            return devA < devB ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }

    /// Getal voor getal, ontbrekende delen tellen als 0.
    static func compare(_ a: [Int], _ b: [Int]) -> ComparisonResult {
        for i in 0..<max(a.count, b.count) {
            let (l, r) = (i < a.count ? a[i] : 0, i < b.count ? b[i] : 0)
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// semver 2.0.0 §11: getallen als getal, een getal vóór een woord, en een korter rijtje vóór
    /// een langer met hetzelfde begin. Bekende woorden in hun eigen volgorde (dev < alpha < beta <
    /// rc), zodat Composer en PEP 440 (`a`, `b`, `c`) ook kloppen; andere woorden op de letter.
    static func compare(prerelease a: [String], _ b: [String]) -> ComparisonResult {
        for (l, r) in zip(a, b) where l != r {
            switch (Int(l), Int(r)) {
            case let (x?, y?):
                if x != y { return x < y ? .orderedAscending : .orderedDescending }
            case (_?, nil):
                return .orderedAscending
            case (nil, _?):
                return .orderedDescending
            case (nil, nil):
                if let x = rank[l], let y = rank[r] {
                    if x != y { return x < y ? .orderedAscending : .orderedDescending }
                } else {
                    return l < r ? .orderedAscending : .orderedDescending
                }
            }
        }
        if a.count != b.count { return a.count < b.count ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }

    private static let rank: [String: Int] = [
        "dev": 0, "a": 1, "alpha": 1, "b": 2, "beta": 2, "c": 3, "rc": 3, "pre": 3, "preview": 3,
    ]

    /// PEP 440 schrijft een post-release ook als `rev` of `r`; Composer als `patch`, `pl` of `p`.
    private static let postWords: Set<String> = ["post", "rev", "r", "patch", "pl", "p"]

    /// "-beta.11" → ["beta", "11"]; "a1.post2" → ["a", "1", "post", "2"]. Scheiders zijn `.`, `-`
    /// en `_`, en de grens tussen letters en cijfers.
    private static func tokens(_ tail: Substring) -> [String] {
        var result: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { result.append(current) }
            current = ""
        }
        for character in tail {
            if character == "." || character == "-" || character == "_" {
                flush()
                continue
            }
            if let last = current.last, last.isNumber != character.isNumber { flush() }
            current.append(character)
        }
        flush()
        return result
    }
}

/// Hoe groot een stap van de ene naar de andere versie is.
public enum UpdateStep: String, Codable, Hashable, Sendable, Comparable {
    case patch, minor, major

    /// Het eerste releasedeel dat verschilt; nil als `to` niet nieuwer is.
    public init?(from: Version, to: Version) {
        guard from < to else { return nil }
        if from.epoch != to.epoch || from.part(0) != to.part(0) {
            self = .major
        } else if from.part(1) != to.part(1) {
            self = .minor
        } else {
            self = .patch
        }
    }

    private var order: Int {
        switch self {
        case .patch: 0
        case .minor: 1
        case .major: 2
        }
    }

    public static func < (lhs: UpdateStep, rhs: UpdateStep) -> Bool { lhs.order < rhs.order }
}

extension StringProtocol {
    /// Zonder de "v" vooraan die Go-modules en tags hebben: "v1.2.3" wordt "1.2.3".
    var droppingVersionPrefix: String { hasPrefix("v") ? String(dropFirst()) : String(self) }
}
