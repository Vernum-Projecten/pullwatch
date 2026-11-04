import Foundation

/// Eén onderdeel (taal, runtime, framework of Docker-image) van een repo met zijn status.
public struct ComponentVersion: Codable, Hashable, Sendable {
    public let product: String
    public let label: String
    /// Oudste gevonden versie als het onderdeel in meerdere bestanden staat.
    public let version: String
    public let latest: String?
    public let status: VersionStatus
    public let sources: [String]
    /// Releasecyclus van `version` (bv. "1.26") en de nieuwste patch daarin; nil als onbekend.
    let cycle: String?
    let cycleLatest: String?

    public init(
        product: String, label: String, version: String, latest: String?, status: VersionStatus, sources: [String],
        cycle: String? = nil, cycleLatest: String? = nil
    ) {
        self.product = product
        self.label = label
        self.version = version
        self.latest = latest
        self.status = status
        self.sources = sources
        self.cycle = cycle
        self.cycleLatest = cycleLatest
    }
}

/// Dezelfde check op de nieuwste tag: wat er in de laatste release zit.
public struct ReleaseVersions: Codable, Hashable, Sendable {
    public let tag: String
    public let components: [ComponentVersion]
    /// Ernstigste eerst.
    public let vulnerabilities: [Vulnerability]
    /// Gezet als de tag niet te scannen was; de check van de default branch staat dan nog wel.
    public let error: String?
    /// Bronnen die voor deze tag uit stonden en dus niets gecontroleerd hebben (zie `RepoVersions.skippedSources`).
    public let skippedSources: Set<DataSourceID>

    public init(
        tag: String, components: [ComponentVersion], vulnerabilities: [Vulnerability] = [], error: String? = nil,
        skippedSources: Set<DataSourceID> = []
    ) {
        self.tag = tag
        self.components = components
        self.vulnerabilities = vulnerabilities
        self.error = error
        self.skippedSources = skippedSources
    }

    /// Stond `id` uit, zodat er voor deze tag niets over te zeggen is?
    public func isUnchecked(_ id: DataSourceID) -> Bool { skippedSources.contains(id) }

    private enum CodingKeys: String, CodingKey {
        case tag, components, vulnerabilities, error, skippedSources
    }

    /// versions.json van vóór de bronnen heeft geen `skippedSources`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tag = try c.decode(String.self, forKey: .tag)
        components = try c.decode([ComponentVersion].self, forKey: .components)
        vulnerabilities = try c.decode([Vulnerability].self, forKey: .vulnerabilities)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        skippedSources = try DataSourceID.decodeTolerantly(from: c, forKey: .skippedSources)
    }
}

/// De uitkomst van de versiecheck voor één repo: onderdelen, kwetsbaarheden, packages en beveiliging.
public struct RepoVersions: Codable, Hashable, Sendable, Identifiable {
    public let accountId: UUID
    public let repo: String
    public let components: [ComponentVersion]
    public let error: String?
    /// Ernstigste eerst.
    public let vulnerabilities: [Vulnerability]
    /// Gezet als de CVE-check voor deze repo niet kon draaien (OSV onbereikbaar).
    public let vulnerabilityError: String?
    /// Adviezen die hun database heeft ingetrokken (OSV `withdrawn`): niet in `vulnerabilities`,
    /// niet in status, telling of meldingen; alleen apart genoemd.
    public let withdrawnVulnerabilities: [Vulnerability]
    /// Check van de nieuwste tag; nil als de repo geen tags met een versienummer heeft. Alleen ter info:
    /// status, sortering en meldingen gaan over de default branch.
    public let release: ReleaseVersions?
    /// Direct gebruikte packages op de default branch, voor het overzicht per package; elk met al
    /// zijn installs (versies, workspaces, ook transitief).
    public let packages: [PackageUse]
    /// Packages die de repo nergens zelf vraagt (alleen transitief, of zonder manifest om het te
    /// bepalen), met hun installs; voor de repo-pagina en "alleen transitief" in Versies.
    public let otherPackages: [PackageUse]
    /// Beveiligingsgegevens van de dienst zelf (code scanning, geheimen, eigen adviezen, Advanced
    /// Security); nil als de dienst die niet kent of het ophalen mislukte.
    public let security: SecurityScan?
    /// Bronnen die uit stonden en voor deze repo iets hadden moeten controleren: daarover zegt de
    /// check niets, ook niet "in orde". OSV alleen als de repo packages heeft, de beveiliging van
    /// de dienst alleen bij een account van die dienst.
    public let skippedSources: Set<DataSourceID>

    public var id: String { "\(accountId.uuidString)/\(repo)" }

    /// Slechtste status van de onderdelen; een fout telt als onbekend. Alleen de default branch telt:
    /// wat daar al opgelost is, hoeft niet gemeld te worden.
    var worstStatus: VersionStatus? {
        if error != nil { return .unknown }
        return components.map(\.status).max()
    }

    /// Voor sorteren: een kwetsbaarheid weegt even zwaar als EOL.
    public var severity: Int {
        max(worstStatus?.severity ?? -1, vulnerabilities.isEmpty ? -1 : VersionStatus.eol.severity)
    }

    /// Aantal adviezen (lek per package), hoeveel installs elk ook raakt.
    public var advisoryCount: Int { Set(vulnerabilities.map(\.key)).count }

    /// Stond `id` uit, zodat de check er voor deze repo niets over zegt?
    public func isUnchecked(_ id: DataSourceID) -> Bool { skippedSources.contains(id) }

    /// Zit deze kwetsbaarheid van de default branch ook in de laatste release? nil zonder (bruikbare) release.
    public func isInRelease(_ vulnerability: Vulnerability) -> Bool? {
        guard let release, release.error == nil else { return nil }
        return release.vulnerabilities.contains { $0.key == vulnerability.key }
    }

    public init(
        accountId: UUID,
        repo: String,
        components: [ComponentVersion],
        error: String? = nil,
        vulnerabilities: [Vulnerability] = [],
        vulnerabilityError: String? = nil,
        withdrawnVulnerabilities: [Vulnerability] = [],
        release: ReleaseVersions? = nil,
        packages: [PackageUse] = [],
        otherPackages: [PackageUse] = [],
        security: SecurityScan? = nil,
        skippedSources: Set<DataSourceID> = []
    ) {
        self.accountId = accountId
        self.repo = repo
        self.components = components
        self.error = error
        self.vulnerabilities = vulnerabilities
        self.vulnerabilityError = vulnerabilityError
        self.withdrawnVulnerabilities = withdrawnVulnerabilities
        self.release = release
        self.packages = packages
        self.otherPackages = otherPackages
        self.security = security
        self.skippedSources = skippedSources
    }

    private enum CodingKeys: String, CodingKey {
        case accountId, repo, components, error, vulnerabilities, vulnerabilityError, withdrawnVulnerabilities, release, packages
        case otherPackages, security, skippedSources
    }

    /// versions.json van vóór de CVE-check heeft geen `vulnerabilities`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try c.decode(UUID.self, forKey: .accountId)
        repo = try c.decode(String.self, forKey: .repo)
        components = try c.decode([ComponentVersion].self, forKey: .components)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        vulnerabilities = try c.decodeIfPresent([Vulnerability].self, forKey: .vulnerabilities) ?? []
        vulnerabilityError = try c.decodeIfPresent(String.self, forKey: .vulnerabilityError)
        withdrawnVulnerabilities = try c.decodeIfPresent([Vulnerability].self, forKey: .withdrawnVulnerabilities) ?? []
        release = try c.decodeIfPresent(ReleaseVersions.self, forKey: .release)
        packages = try c.decodeIfPresent([PackageUse].self, forKey: .packages) ?? []
        otherPackages = try c.decodeIfPresent([PackageUse].self, forKey: .otherPackages) ?? []
        security = try c.decodeIfPresent(SecurityScan.self, forKey: .security)
        skippedSources = try DataSourceID.decodeTolerantly(from: c, forKey: .skippedSources)
    }
}

extension DataSourceID {
    /// Een bron die deze versie niet kent (uit een nieuwere versions.json) valt weg; de rest blijft.
    static func decodeTolerantly<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> Set<DataSourceID> {
        Set((try container.decodeIfPresent([String].self, forKey: key) ?? []).compactMap(DataSourceID.init(rawValue:)))
    }
}
