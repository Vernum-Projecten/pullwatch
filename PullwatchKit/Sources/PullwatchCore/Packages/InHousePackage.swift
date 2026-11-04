public import Foundation

/// Een dependency die een gevolgde repository (of een Azure-project) zelf publiceert: de versiecheck
/// neemt de nieuwste versie uit dat eigen register in plaats van het publieke, en vraagt het
/// publieke register niets over deze naam. Bewaard op de metadata van het package
/// (`PackageMetadata.inHouse`), zodat de app en de MCP-tools het zonder extra pad lezen.
public struct InHousePackage: Codable, Hashable, Sendable {
    /// Of de check de versies uit het eigen register kon lezen.
    public enum Status: Hashable, Sendable {
        /// Gelezen: de nieuwste versie en de versies komen uit het eigen register.
        case checked
        /// De bron Packageregisters van je accounts staat uit: niet gecontroleerd.
        case sourceOff
        /// Het account mag het register niet lezen; `reason` zegt wat er nodig is.
        case needsPermission(reason: String)
    }

    /// Het account waarvan het register het package noemt.
    public let accountId: UUID
    /// De naam in het register ("@acme/ui", "ui" bij GitHub, "com.acme.ui" bij Maven).
    public let name: String
    public let type: PublishedPackageType
    /// De gebruiker, organisatie, groep of het Azure-project waar het package onder staat.
    public let owner: String
    /// De repository die het publiceert (`Account.repoWatch`-vorm); nil als de dienst het package
    /// aan geen repository koppelt (Azure Artifacts: dan is `owner` het project).
    public let repository: String?
    /// De pagina van die repository bij de dienst.
    public let repositoryURL: URL?
    /// De pagina van het package bij het register.
    public let registryURL: URL?
    public let status: Status

    public init(
        accountId: UUID, name: String, type: PublishedPackageType, owner: String, repository: String?,
        repositoryURL: URL? = nil, registryURL: URL? = nil, status: Status = .checked
    ) {
        self.accountId = accountId
        self.name = name
        self.type = type
        self.owner = owner
        self.repository = repository
        self.repositoryURL = repositoryURL
        self.registryURL = registryURL
        self.status = status
    }

    /// Wat het package publiceert: de repository, anders de eigenaar (het Azure-project).
    public var source: String { repository ?? owner }

    /// De link voor "In-house": de repository, anders de pagina in het register.
    public var link: URL? { repositoryURL ?? registryURL }

    /// Of de nieuwste versie uit het eigen register komt; anders is het package niet gecontroleerd.
    public var isChecked: Bool { status == .checked }

    /// Dezelfde herkomst met een andere stand.
    public func with(status: Status) -> InHousePackage {
        InHousePackage(
            accountId: accountId, name: name, type: type, owner: owner, repository: repository,
            repositoryURL: repositoryURL, registryURL: registryURL, status: status
        )
    }

    // MARK: - Lezen en schrijven

    private enum CodingKeys: String, CodingKey {
        case accountId, name, type, owner, repository, repositoryURL, registryURL, status, reason
    }

    private enum StatusKey: String, Codable {
        case checked, sourceOff, needsPermission
    }

    /// Account, naam, soort en eigenaar zijn nodig; de rest mag ontbreken. Een stand die Pullwatch
    /// niet kent (van een nieuwere versie) leest als `.sourceOff`: liever "niet gecontroleerd" dan
    /// een oude versie als actueel.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try c.decode(UUID.self, forKey: .accountId)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(PublishedPackageType.self, forKey: .type)
        owner = try c.decode(String.self, forKey: .owner)
        repository = try? c.decodeIfPresent(String.self, forKey: .repository)
        repositoryURL = try? c.decodeIfPresent(URL.self, forKey: .repositoryURL)
        registryURL = try? c.decodeIfPresent(URL.self, forKey: .registryURL)
        switch try? c.decodeIfPresent(StatusKey.self, forKey: .status) {
        case .checked?: status = .checked
        case .needsPermission?: status = .needsPermission(reason: (try? c.decodeIfPresent(String.self, forKey: .reason)) ?? "")
        case .sourceOff?, nil: status = .sourceOff
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accountId, forKey: .accountId)
        try c.encode(name, forKey: .name)
        try c.encode(type, forKey: .type)
        try c.encode(owner, forKey: .owner)
        try c.encodeIfPresent(repository, forKey: .repository)
        try c.encodeIfPresent(repositoryURL, forKey: .repositoryURL)
        try c.encodeIfPresent(registryURL, forKey: .registryURL)
        switch status {
        case .checked:
            try c.encode(StatusKey.checked, forKey: .status)
        case .sourceOff:
            try c.encode(StatusKey.sourceOff, forKey: .status)
        case .needsPermission(let reason):
            try c.encode(StatusKey.needsPermission, forKey: .status)
            try c.encode(reason, forKey: .reason)
        }
    }
}
