import Foundation

/// Wat een register over één versie van een package zegt, voor zover een update erop kan
/// stranden: wat die versie zelf vraagt (packages, peers, runtimes).
public struct VersionMetadata: Codable, Hashable, Sendable {
    /// Runtime-afhankelijkheden: naam → bereik in de syntaxis van het ecosysteem. nil als het
    /// register ze per versie apart geeft (crates.io, RubyGems, PyPI, Go) en ze nog niet opgehaald zijn.
    public var dependencies: [String: String]?
    /// npm `peerDependencies`: wat naast dit package in de workspace moet staan.
    public var peerDependencies: [String: String]
    /// Peers die `peerDependenciesMeta` optioneel noemt.
    var optionalPeers: [String]
    /// Eisen aan de runtime, per product zoals endoflife.date het noemt (`nodejs`, `php`, `python`,
    /// `rust`, `dotnet`, `ruby`, `rubygems`, `go`), in de syntaxis van het ecosysteem. Voor Rust, Go
    /// en .NET een minimum (`>= 1.70`).
    public var runtimes: [String: String]
    /// Ingetrokken (yanked, unlisted, deprecated): telt niet als bruikbare versie.
    var isWithdrawn: Bool

    public init(
        dependencies: [String: String]? = nil, peerDependencies: [String: String] = [:], optionalPeers: [String] = [],
        runtimes: [String: String] = [:], isWithdrawn: Bool = false
    ) {
        self.dependencies = dependencies
        self.peerDependencies = peerDependencies
        self.optionalPeers = optionalPeers
        self.runtimes = runtimes
        self.isWithdrawn = isWithdrawn
    }

    private enum CodingKeys: String, CodingKey {
        case dependencies, peerDependencies, optionalPeers, runtimes, isWithdrawn
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dependencies = try c.decodeIfPresent([String: String].self, forKey: .dependencies)
        peerDependencies = try c.decodeIfPresent([String: String].self, forKey: .peerDependencies) ?? [:]
        optionalPeers = try c.decodeIfPresent([String].self, forKey: .optionalPeers) ?? []
        runtimes = try c.decodeIfPresent([String: String].self, forKey: .runtimes) ?? [:]
        isWithdrawn = try c.decodeIfPresent(Bool.self, forKey: .isWithdrawn) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(dependencies, forKey: .dependencies)
        if !peerDependencies.isEmpty { try c.encode(peerDependencies, forKey: .peerDependencies) }
        if !optionalPeers.isEmpty { try c.encode(optionalPeers, forKey: .optionalPeers) }
        if !runtimes.isEmpty { try c.encode(runtimes, forKey: .runtimes) }
        if isWithdrawn { try c.encode(isWithdrawn, forKey: .isWithdrawn) }
    }
}

/// Het register over één package: de nieuwste versie en per versie (vanaf de oudste die een repo
/// gebruikt) wat die vraagt. Bewaard in `VersionReport.packageMetadata`, zodat wat per versie
/// apart opgehaald wordt (een go.mod, de dependencies van een crate) de volgende check niet
/// opnieuw de deur uit gaat: een gepubliceerde versie verandert niet.
public struct PackageMetadata: Codable, Hashable, Sendable {
    /// Nieuwste stabiele versie, zoals `PackageRegistry.latest` die geeft.
    public var latest: String?
    /// Versie → metadata; alleen stabiele versies vanaf de oudste install, plus de installs zelf.
    public var versions: [String: VersionMetadata]
    /// false zolang alleen de nieuwste versie bekend is (Go: `@latest` zonder `@v/list`).
    public var isComplete: Bool
    /// Gezet als een gevolgde repository dit package zelf publiceert: dan komen `latest` en
    /// `versions` uit dat eigen register en is het publieke register niet gevraagd.
    public var inHouse: InHousePackage?

    public init(latest: String?, versions: [String: VersionMetadata], isComplete: Bool = true, inHouse: InHousePackage? = nil) {
        self.latest = latest
        self.versions = versions
        self.isComplete = isComplete
        self.inHouse = inHouse
    }

    private enum CodingKeys: String, CodingKey {
        case latest, versions, isComplete, inHouse
    }

    /// Een rapport van vóór de eigen packages heeft geen `inHouse`; een onleesbare wordt nil.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        latest = try c.decodeIfPresent(String.self, forKey: .latest)
        versions = try c.decodeIfPresent([String: VersionMetadata].self, forKey: .versions) ?? [:]
        isComplete = try c.decodeIfPresent(Bool.self, forKey: .isComplete) ?? true
        inHouse = (try? c.decodeIfPresent(InHousePackage.self, forKey: .inHouse)) ?? nil
    }

    /// De versies die een update kunnen zijn, oplopend: stabiel, niet ingetrokken en leesbaar.
    var candidates: [(text: String, version: Version, metadata: VersionMetadata)] {
        versions.compactMap { text, metadata in
            guard let version = Version(text), !version.isPrerelease, !metadata.isWithdrawn else { return nil }
            return (text, version, metadata)
        }
        .sorted { $0.version < $1.version }
    }

    /// De metadata van `version`, ook als het register hem anders schrijft ("v1.2.0", "1.2").
    func metadata(for version: String) -> VersionMetadata? {
        if let exact = versions[version] { return exact }
        guard let wanted = Version(version) else { return nil }
        return versions.first { Version($0.key) == wanted }?.value
    }

    /// Neemt per-versie-gegevens uit `cached` over die dit antwoord niet heeft (opgehaalde
    /// dependencies, een go.mod).
    func filling(from cached: PackageMetadata?) -> PackageMetadata {
        guard let cached else { return self }
        var result = self
        for (version, old) in cached.versions {
            guard var current = result.versions[version] else { continue }
            if current.dependencies == nil, let dependencies = old.dependencies {
                current.dependencies = dependencies
                for (runtime, requirement) in old.runtimes where current.runtimes[runtime] == nil {
                    current.runtimes[runtime] = requirement
                }
            }
            result.versions[version] = current
        }
        return result
    }
}

/// Een eis aan de runtime (`VersionMetadata.runtimes`) als bereik.
enum RuntimeRequirement {
    static func range(runtime: String, requirement: String) -> VersionRange? {
        switch runtime {
        case "nodejs": return NpmRange.parse(requirement)
        case "php": return ComposerConstraint.parse(requirement)
        case "python": return PEP440Specifier.parse(requirement)
        case "ruby", "rubygems": return GemRequirement.parse(requirement)
        default:
            // Rust, Go en .NET: een minimum.
            let text = requirement.replacing(/^\s*>=\s*/, with: "")
            return Version(text).map { VersionRange([[VersionRange.Comparator(.greaterOrEqual, $0)]]) }
        }
    }

    /// Of een runtime `installed` aan `requirement` voldoet. Een deels geschreven versie ("18",
    /// "8.2") is een hele cyclus: die voldoet als het begin of het eind van de cyclus erin valt.
    static func isSatisfied(runtime: String, requirement: String, installed: String) -> Bool? {
        guard let range = range(runtime: runtime, requirement: requirement), let version = Version(installed) else { return nil }
        if range.contains(version) { return true }
        guard version.release.count < 3 else { return false }
        let top = Version(release: version.release + Array(repeating: 9999, count: 3 - version.release.count))
        return range.contains(top)
    }
}
