import PullwatchCore

/// Wat Pullwatch niet controleerde omdat een bron uit staat, in de zin die de tools geven:
/// "Not checked: source OSV.dev is off." Een bron die uit staat lijkt zo nooit op "in orde",
/// net als in de vensters.
struct MCPSourceOff: Encodable, Hashable {
    /// `DataSourceID.rawValue`, zoals `get_status` de bronnen noemt.
    let source: String
    let message: String
    /// Over welke repo het gaat; nil als het voor alles geldt.
    let repository: String?

    init(_ id: DataSourceID, repository: String? = nil, detail: String? = nil) {
        source = id.rawValue
        message = "Not checked: source \(Self.name(id)) is off" + (detail.map { " (\($0))" } ?? "") + "."
        self.repository = repository
    }

    /// Een eigen package dat het account niet mag lezen: de bron staat aan, maar het token mist het recht.
    init(permission reason: String?, repository: String? = nil) {
        source = DataSourceID.packageRegistries.rawValue
        message = "Not checked: Pullwatch has no permission to read this account's package registry"
            + (reason.map { " (\($0))" } ?? "") + "."
        self.repository = repository
    }

    /// Een eigen package waarvan het eigen register geen nieuwste versie gaf (#215): de bron staat
    /// aan, maar het lezen mislukte.
    init(readFailedFor repository: String?) {
        source = DataSourceID.packageRegistries.rawValue
        message = "Not checked: reading the latest version from this account's package registry failed."
        self.repository = repository
    }

    /// Een eigen package volgens de lockfile, dat het register van het account niet noemde (#216).
    init(unconfirmedFor repository: String?) {
        source = DataSourceID.packageRegistries.rawValue
        message = "Not checked: the lockfile installs it from this account's own package registry, but that registry did not list it."
        self.repository = repository
    }

    /// De Engelse naam van de bron ("OSV.dev", "GitHub security").
    static func name(_ id: DataSourceID) -> String {
        AgentBrief.englishName(id)
    }

    static let schema = MCPSchema.object(
        [
            "source": .string("The data source that is off, as get_status lists it.", oneOf: DataSourceID.allCases.map(\.rawValue)),
            "message": .string("What Pullwatch did not check. Never read this as clean."),
            "repository": .string("The repository it is about; absent when it applies to every repository."),
        ],
        required: ["source", "message"]
    )

    /// De bronnen die voor `versions` uit stonden, in de volgorde van het tabblad Bronnen.
    static func skipped(_ versions: RepoVersions, repository: String? = nil) -> [MCPSourceOff] {
        DataSource.all.map(\.id).filter(versions.isUnchecked).map { MCPSourceOff($0, repository: repository) }
    }
}
