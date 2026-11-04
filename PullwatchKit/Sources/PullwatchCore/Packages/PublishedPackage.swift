public import Foundation

/// Een package dat een gevolgde repository (of de eigenaar zelf) in het register van de dienst
/// publiceert: een npm-package, een container-image, een NuGet-package. Eén per package, niet per
/// versie; de recente versies staan in `versions`, nieuwste eerst.
public struct PublishedPackage: Codable, Hashable, Sendable, Identifiable {
    /// Wie het package kan zien.
    public enum Visibility: String, Codable, Sendable {
        case `public`, `private`, `internal`
    }

    /// Wat `latestVersion` is. Een container-image zonder versietag toont een zwevende tag, in
    /// het grijs; zonder enige tag niets.
    public enum LatestKind: String, Codable, Hashable, Sendable {
        /// Een versie zoals het register hem noemt, of bij een image de hoogste versietag.
        case version
        /// Geen versietag: de nieuwste zwevende tag (`main`, `latest`).
        case floatingTag
        /// Geen enkele image heeft een tag die iets zegt.
        case untagged
    }

    /// Waar de tag `latest` van een image naar wijst, ten opzichte van `latestVersion`.
    public enum LatestTag: Codable, Hashable, Sendable {
        /// Geen `latest` (of geen image).
        case absent
        /// Op de image van de nieuwste versie.
        case onLatestVersion
        /// Op een image met een andere versietag.
        case otherVersion(String)
        /// Op een image zonder versietag, een build van een branch.
        case unversionedBuild
    }

    /// Hoeveel versies Pullwatch per package bewaart: genoeg voor "wie zit op welke versie",
    /// geen volledige geschiedenis (die staat bij het register zelf).
    public static let recentVersionLimit = 10

    /// Uniek binnen een account: eigenaar, soort en naam ("acme/npm/@acme/ui").
    public var id: String { "\(owner.lowercased())/\(type.rawValue)/\(name)" }
    public let accountId: UUID
    /// De naam in het register ("@acme/ui", "acme/web" voor een image).
    public let name: String
    public let type: PublishedPackageType
    /// De gebruiker, organisatie, groep of het project waar het package onder staat.
    public let owner: String
    /// De gevolgde repository die het publiceert, in de vorm van `Account.repoWatch`; nil als de
    /// dienst het package aan geen repository koppelt.
    public let repository: String?
    /// De nieuwste versie; nil als de dienst die niet noemt en de versies niet gevraagd zijn.
    public let latestVersion: String?
    /// Wanneer de nieuwste versie verscheen, of anders wanneer het package laatst veranderde.
    public let publishedAt: Date?
    public let visibility: Visibility?
    /// De pagina van het package bij het register.
    public let webURL: URL?
    /// De recente versies, nieuwste eerst, hooguit `recentVersionLimit`.
    public let versions: [PublishedVersion]
    /// Wat `latestVersion` is; `.version` bij elk ander soort package en in oudere gegevens.
    public let latestKind: LatestKind
    /// Waar `latest` naar wijst; alleen bij een container-image iets anders dan `.absent`.
    public let latestTag: LatestTag

    public init(
        accountId: UUID, name: String, type: PublishedPackageType, owner: String, repository: String?,
        latestVersion: String? = nil, publishedAt: Date? = nil, visibility: Visibility? = nil, webURL: URL? = nil,
        versions: [PublishedVersion] = [], latestKind: LatestKind = .version, latestTag: LatestTag = .absent
    ) {
        self.accountId = accountId
        self.name = name
        self.type = type
        self.owner = owner
        self.repository = repository
        self.versions = Array(versions.prefix(Self.recentVersionLimit))
        self.latestVersion = latestVersion ?? versions.first?.version
        self.publishedAt = publishedAt ?? versions.first?.publishedAt
        self.visibility = visibility
        self.webURL = webURL
        self.latestKind = latestKind
        self.latestTag = latestTag
    }

    /// Een container-image uit zijn tags: de nieuwste versie, de datum en de recente versies uit
    /// `ContainerVersions`.
    public init(
        accountId: UUID, name: String, type: PublishedPackageType, owner: String, repository: String?,
        container: ContainerVersions, fallbackDate: Date? = nil, visibility: Visibility? = nil, webURL: URL? = nil
    ) {
        self.init(
            accountId: accountId, name: name, type: type, owner: owner, repository: repository,
            latestVersion: container.latestVersion, publishedAt: container.publishedAt ?? fallbackDate, visibility: visibility,
            webURL: webURL, versions: container.versions, latestKind: container.latestKind, latestTag: container.latestTag
        )
    }

    /// De nieuwste versie als echte versie: nil bij een zwevende tag of zonder tag. Dit vergelijkt
    /// de check op eigen packages en de melding van een nieuwe versie.
    public var releasedVersion: String? { latestKind == .version ? latestVersion : nil }

    private enum CodingKeys: String, CodingKey {
        case accountId, name, type, owner, repository, latestVersion, publishedAt, visibility, webURL, versions, latestKind, latestTag
    }

    /// Naam, soort, eigenaar en account zijn nodig; de rest mag ontbreken of onbekend zijn (een
    /// zichtbaarheid die Pullwatch niet kent wordt nil, een kapotte versie valt weg).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try c.decode(UUID.self, forKey: .accountId)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(PublishedPackageType.self, forKey: .type)
        owner = try c.decode(String.self, forKey: .owner)
        repository = try? c.decodeIfPresent(String.self, forKey: .repository)
        latestVersion = try? c.decodeIfPresent(String.self, forKey: .latestVersion)
        publishedAt = try? c.decodeIfPresent(Date.self, forKey: .publishedAt)
        visibility = try? c.decodeIfPresent(Visibility.self, forKey: .visibility)
        webURL = try? c.decodeIfPresent(URL.self, forKey: .webURL)
        versions = ((try? c.decodeIfPresent([Lossy<PublishedVersion>].self, forKey: .versions)) ?? []).compactMap(\.value)
        // Ontbreekt in gegevens van voor #209, of een waarde van een nieuwere Pullwatch: een versie.
        latestKind = (try? c.decodeIfPresent(LatestKind.self, forKey: .latestKind)) ?? .version
        latestTag = (try? c.decodeIfPresent(LatestTag.self, forKey: .latestTag)) ?? .absent
    }
}
