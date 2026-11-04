import Foundation

/// Hoe een package in een project komt.
public enum DependencyScope: String, Codable, Hashable, Sendable {
    /// Het project vraagt het zelf (manifest, root van de lockfile of een workspace).
    case direct
    /// Alleen via een ander package.
    case transitive
    /// Niet uit de bestanden af te leiden (bv. Package.resolved, of een lockfile zonder manifest).
    case unknown
}

/// Waarvoor een package nodig is.
public enum DependencyKind: String, Codable, Hashable, Sendable {
    case runtime
    /// Alleen voor ontwikkelen en testen (`devDependencies`, `packages-dev`, poetry-groep dev).
    case dev
    /// Optioneel (`optionalDependencies`, extras).
    case optional

    /// Volgorde bij samenvoegen: wat bij runtime nodig is, weegt het zwaarst.
    var weight: Int {
        switch self {
        case .runtime: 2
        case .optional: 1
        case .dev: 0
        }
    }
}

/// Een package met exacte versie uit een lockfile of manifest, in OSV-termen: één install.
public struct Dependency: Hashable, Sendable {
    /// OSV-ecosysteem: "Go", "npm", "NuGet", "PyPI", "Packagist", "crates.io", "RubyGems" of "SwiftURL".
    public let ecosystem: String
    public let name: String
    public let version: String
    public let source: String
    /// Map van het manifest of de lockfile (of de npm/uv-workspace) waar het bij hoort; "" is de root.
    public let workspace: String
    public let scope: DependencyScope
    public let kind: DependencyKind
    /// Kortste keten van packagenamen vanaf een direct package, zonder dit package zelf; leeg als direct.
    public let via: [String]
    /// Het gevraagde bereik zoals geschreven: uit het manifest voor een directe install, uit de
    /// ouder in `via` voor een transitieve (als de lockfile dat bewaart); nil als onbekend.
    public let requested: String?

    public init(
        ecosystem: String, name: String, version: String, source: String,
        workspace: String?, scope: DependencyScope, kind: DependencyKind = .runtime, via: [String] = [],
        requested: String? = nil
    ) {
        self.ecosystem = ecosystem
        self.name = name
        self.version = version
        self.source = source
        self.workspace = workspace ?? DependencyDetector.folder(of: source)
        self.scope = scope
        self.kind = kind
        self.via = via
        self.requested = requested
    }

    /// Oude vorm: `isDirect` true, false of nil (onbekend); workspace volgt uit `source`.
    public init(ecosystem: String, name: String, version: String, source: String, isDirect: Bool? = nil, requested: String? = nil) {
        self.init(ecosystem: ecosystem, name: name, version: version, source: source, workspace: nil, scope: DependencyScope(isDirect: isDirect),
                  requested: requested)
    }

    /// Rechtstreeks gevraagd (true), alleen via een ander package (false) of onbekend (nil).
    var isDirect: Bool? {
        switch scope {
        case .direct: true
        case .transitive: false
        case .unknown: nil
        }
    }

    /// Zelfde package en versie, ongeacht bestand, workspace en herkomst; sleutel voor de OSV-query.
    var withoutSource: Dependency {
        Dependency(ecosystem: ecosystem, name: name, version: version, source: "", workspace: "", scope: .unknown)
    }

    /// Eén install per package, versie en workspace; een tweede bestand in dezelfde map telt niet apart.
    var installKey: String { "\(ecosystem)|\(name)|\(version)|\(workspace)" }

    func with(scope: DependencyScope? = nil, kind: DependencyKind? = nil, via: [String]? = nil, requested: String?? = nil) -> Dependency {
        Dependency(
            ecosystem: ecosystem, name: name, version: version, source: source, workspace: workspace,
            scope: scope ?? self.scope, kind: kind ?? self.kind, via: via ?? self.via, requested: requested ?? self.requested
        )
    }

    var install: PackageInstall {
        PackageInstall(version: version, workspace: workspace, scope: scope, kind: kind, via: via, source: source, requested: requested)
    }
}

extension DependencyScope {
    init(isDirect: Bool?) {
        switch isDirect {
        case true?: self = .direct
        case false?: self = .transitive
        case nil: self = .unknown
        }
    }
}

extension Dependency: Codable {
    private enum CodingKeys: String, CodingKey {
        case ecosystem, name, version, source, workspace, scope, kind, via, requested
        /// Alleen lezen: oude bestanden hadden `isDirect` in plaats van `scope`.
        case isDirect
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let source = try c.decode(String.self, forKey: .source)
        let scope = try c.decodeIfPresent(DependencyScope.self, forKey: .scope)
            ?? DependencyScope(isDirect: try c.decodeIfPresent(Bool.self, forKey: .isDirect))
        self.init(
            ecosystem: try c.decode(String.self, forKey: .ecosystem),
            name: try c.decode(String.self, forKey: .name),
            version: try c.decode(String.self, forKey: .version),
            source: source,
            workspace: try c.decodeIfPresent(String.self, forKey: .workspace),
            scope: scope,
            kind: try c.decodeIfPresent(DependencyKind.self, forKey: .kind) ?? .runtime,
            via: try c.decodeIfPresent([String].self, forKey: .via) ?? [],
            requested: try c.decodeIfPresent(String.self, forKey: .requested)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ecosystem, forKey: .ecosystem)
        try c.encode(name, forKey: .name)
        try c.encode(version, forKey: .version)
        try c.encode(source, forKey: .source)
        try c.encode(workspace, forKey: .workspace)
        try c.encode(scope, forKey: .scope)
        try c.encode(kind, forKey: .kind)
        try c.encode(via, forKey: .via)
        try c.encodeIfPresent(requested, forKey: .requested)
    }
}

/// Eén install van een package in een repo: welke versie, waar en hoe.
public struct PackageInstall: Codable, Hashable, Sendable {
    public let version: String
    /// Map van het manifest of de lockfile; "" is de root.
    public let workspace: String
    public let scope: DependencyScope
    public let kind: DependencyKind
    /// Kortste keten vanaf een direct package; leeg als direct.
    public let via: [String]
    public let source: String
    /// Het gevraagde bereik (`Dependency.requested`); nil als onbekend en in versions.json van
    /// vóór de bereiken.
    public let requested: String?

    public init(
        version: String, workspace: String, scope: DependencyScope, kind: DependencyKind = .runtime, via: [String] = [], source: String,
        requested: String? = nil
    ) {
        self.version = version
        self.workspace = workspace
        self.scope = scope
        self.kind = kind
        self.via = via
        self.source = source
        self.requested = requested
    }

    private enum CodingKeys: String, CodingKey {
        case version, workspace, scope, kind, via, source, requested
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version)
        source = try c.decode(String.self, forKey: .source)
        workspace = try c.decodeIfPresent(String.self, forKey: .workspace) ?? DependencyDetector.folder(of: source)
        scope = try c.decodeIfPresent(DependencyScope.self, forKey: .scope) ?? .unknown
        kind = try c.decodeIfPresent(DependencyKind.self, forKey: .kind) ?? .runtime
        via = try c.decodeIfPresent([String].self, forKey: .via) ?? []
        requested = try c.decodeIfPresent(String.self, forKey: .requested)
    }
}

/// Een package dat een repo ergens direct gebruikt, met al zijn installs (ook transitieve en
/// andere versies). Niets wordt samengevouwen: "packages/web op 4.17.21, packages/api op 4.17.15"
/// zijn twee installs.
public struct PackageUse: Codable, Hashable, Sendable {
    public let ecosystem: String
    public let name: String
    /// Op volgorde van vinden.
    public let installs: [PackageInstall]

    public init(ecosystem: String, name: String, installs: [PackageInstall]) {
        self.ecosystem = ecosystem
        self.name = name
        self.installs = installs
    }

    /// Oude vorm: één versie, direct gebruikt in elk van `sources`.
    public init(ecosystem: String, name: String, version: String, sources: [String]) {
        self.init(ecosystem: ecosystem, name: name, installs: sources.map {
            PackageInstall(version: version, workspace: DependencyDetector.folder(of: $0), scope: .direct, source: $0)
        })
    }

    /// Sleutel voor de nieuwste versie in `VersionReport.latestPackages`.
    public var key: String { "\(ecosystem):\(name)" }

    /// Installs die het project zelf vraagt; zonder zulke installs alle.
    var directInstalls: [PackageInstall] {
        let direct = installs.filter { $0.scope == .direct }
        return direct.isEmpty ? installs : direct
    }

    /// Oudste direct gebruikte versie: wat de repo zelf kan bijwerken.
    public var version: String {
        directInstalls.map(\.version).reduce(nil as String?) { oldest, version in
            guard let oldest else { return version }
            return VersionChecker.isOlder(version, than: oldest) ? version : oldest
        } ?? ""
    }

    /// Bestanden van de directe installs, ontdubbeld, op volgorde van vinden.
    public var sources: [String] {
        directInstalls.map(\.source).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    /// Alle gevonden versies, oudste eerst.
    public var versions: [String] {
        Set(installs.map(\.version)).sorted { VersionChecker.isOlder($0, than: $1) || (!VersionChecker.isOlder($1, than: $0) && $0 < $1) }
    }

    private enum CodingKeys: String, CodingKey {
        case ecosystem, name, installs
        /// Alleen lezen: versions.json van vóór de installs had één versie en een lijst bronnen.
        case version, sources
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let ecosystem = try c.decode(String.self, forKey: .ecosystem)
        let name = try c.decode(String.self, forKey: .name)
        if let installs = try c.decodeIfPresent([PackageInstall].self, forKey: .installs) {
            self.init(ecosystem: ecosystem, name: name, installs: installs)
        } else {
            self.init(
                ecosystem: ecosystem, name: name,
                version: try c.decode(String.self, forKey: .version),
                sources: try c.decodeIfPresent([String].self, forKey: .sources) ?? []
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ecosystem, forKey: .ecosystem)
        try c.encode(name, forKey: .name)
        try c.encode(installs, forKey: .installs)
    }
}
