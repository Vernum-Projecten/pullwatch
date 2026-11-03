import Foundation

// De rijen, filters en tellingen van de controle op de repo-pagina: één rij per advies, één rij per
// package per workspace, en de samenvatting bovenaan. De views tonen alleen wat hier staat.

/// Hoe ernstig een kwetsbaarheid of melding is, van onbekend tot kritiek.
public enum SeverityLevel: Int, CaseIterable, Comparable, Hashable, Sendable {
    case unknown, low, moderate, high, critical

    /// Uit "CRITICAL", "HIGH", "MODERATE"/"MEDIUM" of "LOW"; de rest is onbekend.
    public init(_ raw: String?) {
        switch raw?.uppercased() {
        case "CRITICAL": self = .critical
        case "HIGH": self = .high
        case "MODERATE", "MEDIUM": self = .moderate
        case "LOW": self = .low
        default: self = .unknown
        }
    }

    public static func < (lhs: SeverityLevel, rhs: SeverityLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Een versienummer om op te sorteren: op getallen, zodat 4.17.9 vóór 4.17.15 komt. Zonder
/// versie achteraan.
public struct VersionSortKey: Comparable, Hashable, Sendable {
    public let text: String?

    public init(_ text: String?) {
        self.text = text
    }

    public static func < (lhs: VersionSortKey, rhs: VersionSortKey) -> Bool {
        switch (lhs.text, rhs.text) {
        case let (left?, right?): VersionChecker.isOlder(left, than: right)
        case (.some, nil): true
        case (nil, _): false
        }
    }
}

/// Hoe een advies of package in de repo komt, voor het filter en de kolom Waar.
public enum DependencyOrigin: Int, CaseIterable, Comparable, Hashable, Sendable {
    /// Het project vraagt het zelf.
    case direct
    /// Alleen via een ander package.
    case transitive
    /// Niet te bepalen (geen manifest naast de lockfile).
    case unknown
    /// Alleen om te ontwikkelen en te testen.
    case dev

    public static func < (lhs: DependencyOrigin, rhs: DependencyOrigin) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Kwetsbaarheden

/// Eén advies (lek in één package) als rij in de tabel, met alles wat de kolommen en het
/// inspectievenster tonen.
public struct VulnerabilityRow: Hashable, Sendable, Identifiable {
    public let advisory: Advisory
    /// GitHubs eigen gegevens; nil zonder advies in de Advisory Database.
    public let gitHub: GitHubAdvisory?
    /// Of het advies ook in de laatste release zit; nil zonder (bruikbare) release.
    public let inRelease: Bool?
    /// Wat het oplost, per install, elke oplossing één keer.
    public let fixes: [VulnerabilityFix]

    public init(advisory: Advisory, gitHub: GitHubAdvisory?, inRelease: Bool?, context: UpdateContext = .empty) {
        self.advisory = advisory
        self.gitHub = gitHub
        self.inRelease = inRelease
        self.fixes = advisory.installs.map { $0.fix(in: context) }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    public var id: String { advisory.id }
    public var first: Vulnerability { advisory.first }
    public var package: String { first.package }

    /// De ernst uit de beste bron (#96): de CVSS-vector in OSV, de ernst van de database, of
    /// GitHubs advies; met waar die vandaan komt.
    public var assessment: SeverityAssessment { first.severityAssessment(gitHub) }
    public var severity: SeverityLevel { SeverityLevel(assessment.level) }

    /// Het id van het record in zijn eigen database ("GHSA-…", "RUSTSEC-…", "GO-…").
    public var primaryId: String { first.id }

    /// Elk id van dit lek, het hoofd-id eerst: de aliassen van het record en wat alleen GitHubs
    /// advies kent, elk één keer.
    public var identifiers: [String] {
        (first.allIds + [gitHub?.ghsaId, gitHub?.cveId].compactMap { $0 })
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    public var summary: String? { first.summary ?? gitHub?.summary }

    /// Geïnstalleerde versies, oudste eerst, elk één keer.
    public var installedVersions: [String] {
        advisory.installs.map(\.version).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .sorted { VersionChecker.isOlder($0, than: $1) }
    }

    /// De versie die het lek in elke install oplost: de hoogste `fixedIn`; nil als een install er
    /// nog geen heeft.
    public var fixedIn: String? {
        let fixes = advisory.installs.map(\.fixedIn)
        guard !fixes.contains(nil) else { return nil }
        return fixes.compactMap { $0 }.max { VersionChecker.isOlder($0, than: $1) }
    }

    public var hasFix: Bool { advisory.installs.contains { $0.fixedIn != nil } }

    /// De workspaces met een geraakte install, de root eerst.
    public var workspaces: [String] {
        advisory.installs.map(\.workspace).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .sorted { $0.isEmpty || (!$1.isEmpty && $0 < $1) }
    }

    /// Dev als elke install alleen voor ontwikkelen is, anders direct, transitief of onbekend.
    public var origin: DependencyOrigin {
        if advisory.isDevOnly { return .dev }
        if advisory.isDirect { return .direct }
        if advisory.installs.contains(where: { $0.scope == .transitive }) { return .transitive }
        return .unknown
    }

    /// Het eerste package van de keten van een transitieve install ("express"); nil als direct.
    public var parent: String? {
        guard !advisory.isDirect else { return nil }
        return advisory.installs.first { $0.scope == .transitive }?.via.first
    }

    // Sorteersleutels voor de kolommen.
    public var severitySortKey: Int { severity.rawValue }
    public var advisorySortKey: String { primaryId }
    public var installedSortKey: VersionSortKey { VersionSortKey(installedVersions.first) }
    public var fixSortKey: VersionSortKey { VersionSortKey(fixedIn) }
    public var whereSortKey: String { "\(origin.rawValue)|\(workspaces.joined(separator: ","))|\(parent ?? "")" }
    /// Ook in de release eerst, dan alleen main, dan onbekend.
    public var releaseSortKey: Int {
        switch inRelease {
        case true?: 0
        case false?: 1
        case nil: 2
        }
    }
}

/// Een rij in de tabel van kwetsbaarheden: een advies, of één install eronder als het advies
/// er meer heeft. De sorteersleutels zijn die van het advies, zodat installs bij hun advies blijven.
public struct VulnerabilityTableRow: Hashable, Sendable, Identifiable {
    public let row: VulnerabilityRow
    /// nil voor de rij van het advies zelf.
    public let install: Vulnerability?

    public init(row: VulnerabilityRow, install: Vulnerability? = nil) {
        self.row = row
        self.install = install
    }

    public var id: String { install.map { "\(row.id)#\($0.installId)" } ?? row.id }
    /// De installs als rijen onder het advies; leeg met één install.
    public var children: [VulnerabilityTableRow] {
        guard install == nil, row.advisory.installs.count > 1 else { return [] }
        return row.advisory.installs.map { VulnerabilityTableRow(row: row, install: $0) }
    }

    public var severitySortKey: Int { row.severitySortKey }
    public var advisorySortKey: String { row.advisorySortKey }
    public var installedSortKey: VersionSortKey { install.map { VersionSortKey($0.version) } ?? row.installedSortKey }
    public var fixSortKey: VersionSortKey { install.map { VersionSortKey($0.fixedIn) } ?? row.fixSortKey }
    public var whereSortKey: String { row.whereSortKey }
    public var releaseSortKey: Int { row.releaseSortKey }
}

/// Wat de tabel van kwetsbaarheden toont: ernst, herkomst, met oplossing, ook in de release, en
/// een zoekterm.
public struct VulnerabilityFilter: Hashable, Sendable {
    /// Leeg is elke ernst.
    public var severities: Set<SeverityLevel> = []
    /// Leeg is elke herkomst.
    public var origins: Set<DependencyOrigin> = []
    public var onlyWithFix = false
    public var onlyInRelease = false

    public init(severities: Set<SeverityLevel> = [], origins: Set<DependencyOrigin> = [], onlyWithFix: Bool = false, onlyInRelease: Bool = false) {
        self.severities = severities
        self.origins = origins
        self.onlyWithFix = onlyWithFix
        self.onlyInRelease = onlyInRelease
    }

    public var isActive: Bool { !severities.isEmpty || !origins.isEmpty || onlyWithFix || onlyInRelease }

    /// Of `row` erdoor komt; `text` zoekt in ids, package, samenvatting, versies en keten.
    public func matches(_ row: VulnerabilityRow, text: String = "") -> Bool {
        if !severities.isEmpty && !severities.contains(row.severity) { return false }
        if !origins.isEmpty && !origins.contains(row.origin) { return false }
        if onlyWithFix && !row.hasFix { return false }
        if onlyInRelease && row.inRelease != true { return false }
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let haystack = row.identifiers + [row.package, row.summary ?? ""] + row.installedVersions
            + row.workspaces + row.advisory.installs.flatMap(\.via)
        return haystack.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

extension RepoVersions {
    /// Eén rij per advies, met GitHubs gegevens (`RepoSummary.advisories`) en de oplossing in `context`.
    public func vulnerabilityRows(gitHub: [String: GitHubAdvisory] = [:], context: UpdateContext = .empty) -> [VulnerabilityRow] {
        advisories.map { advisory in
            VulnerabilityRow(advisory: advisory, gitHub: gitHub[advisory.first.id], inRelease: isInRelease(advisory.first), context: context)
        }
    }

    /// De taal- en frameworkversies die achterlopen of geen support meer hebben.
    public var outdatedComponents: [ComponentVersion] {
        components.filter { $0.status == .behind || $0.status == .eol }
    }
}

// MARK: - Packages

/// Eén package in één workspace als rij in de tabel: de versies, de nieuwste die nu kan, de
/// nieuwste, en wat je ermee kunt.
public struct RepoPackageRow: Hashable, Sendable, Identifiable {
    public let package: WorkspacePackage
    public let workspace: String
    public let origin: DependencyOrigin
    /// nil als het register geen nieuwste versie gaf.
    public let latest: String?
    /// Elke install met zijn status, op volgorde van `package.installs`; leeg zonder `latest`.
    public let installs: [InstallUpdate]
    /// Eén status voor wat de repo zelf kan bijwerken (de directe installs, anders alle); nil zonder `latest`.
    public let update: PackageUpdate?

    public init(package: WorkspacePackage, workspace: String, origin: DependencyOrigin, latest: String?, context: UpdateContext = .empty) {
        self.package = package
        self.workspace = workspace
        self.origin = origin
        self.latest = latest
        guard latest != nil else {
            self.installs = []
            self.update = nil
            return
        }
        let installs = package.installs.map {
            InstallUpdate(install: $0, update: $0.update(ecosystem: package.ecosystem, name: package.name, latest: latest, context: context))
        }
        self.installs = installs
        let direct = installs.filter { $0.install.scope == .direct }
        self.update = PackageUpdate.combined((direct.isEmpty ? installs : direct).map(\.update))
    }

    public var id: String { "\(workspace)|\(package.id)" }
    public var name: String { package.name }

    /// Wat je met de nieuwste versie kunt; nil als die niet bekend is.
    public var category: UpdateCategory? { update?.status.category }

    /// De install die de status bepaalt: direct eerst.
    public var leading: InstallUpdate? {
        guard let update else { return nil }
        return installs.first { $0.install.scope == .direct && $0.update.status == update.status }
            ?? installs.first { $0.update.status == update.status }
    }

    /// Geïnstalleerde versies, oudste eerst, elk één keer.
    public var installedVersions: [String] {
        package.installs.map(\.version).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .sorted { VersionChecker.isOlder($0, than: $1) }
    }

    /// De nieuwste versie die nu kan, als die anders is dan de nieuwste en nieuwer dan wat er staat.
    public var newestUsable: String? {
        guard let usable = update?.usable, usable != latest, !installedVersions.contains(usable) else { return nil }
        return usable
    }

    /// Of er iets bij te werken is.
    public var hasUpdate: Bool { category.map { $0 != .upToDate } ?? false }

    // Sorteersleutels voor de kolommen.
    public var nameSortKey: String { package.name.lowercased() }
    public var installedSortKey: VersionSortKey { VersionSortKey(installedVersions.first) }
    public var usableSortKey: VersionSortKey { VersionSortKey(newestUsable) }
    public var latestSortKey: VersionSortKey { VersionSortKey(latest) }
    /// Wat je nu kunt eerst, onbekend achteraan.
    public var statusSortKey: Int { category?.rawValue ?? UpdateCategory.allCases.count }
}

/// Een rij in de tabel van packages: een package, of één install eronder als het package in
/// deze workspace meer versies of ketens heeft.
public struct RepoPackageTableRow: Hashable, Sendable, Identifiable {
    public let row: RepoPackageRow
    /// nil voor de rij van het package zelf.
    public let install: PackageInstall?

    public init(row: RepoPackageRow, install: PackageInstall? = nil) {
        self.row = row
        self.install = install
    }

    public var id: String {
        guard let install else { return row.id }
        return "\(row.id)#\(install.version)|\(install.via.joined(separator: ">"))|\(install.source)"
    }

    /// De status van deze install; voor de rij van het package die van het package.
    public var update: InstallUpdate? {
        guard let install else { return row.leading }
        return row.installs.first { $0.install == install }
    }

    public var children: [RepoPackageTableRow] {
        guard install == nil, row.package.installs.count > 1 else { return [] }
        return row.package.installs.map { RepoPackageTableRow(row: row, install: $0) }
    }

    public var nameSortKey: String { row.nameSortKey }
    public var installedSortKey: VersionSortKey { install.map { VersionSortKey($0.version) } ?? row.installedSortKey }
    public var usableSortKey: VersionSortKey { row.usableSortKey }
    public var latestSortKey: VersionSortKey { row.latestSortKey }
    public var statusSortKey: Int { row.statusSortKey }
}

/// Wat de tabel van packages toont: herkomst, status en een zoekterm.
public struct PackageFilter: Hashable, Sendable {
    /// Wat een package toont op status.
    public enum Status: Hashable, Sendable {
        /// Elke nieuwere versie, wat er ook mee kan.
        case hasUpdate
        case category(UpdateCategory)
    }

    /// Leeg is elke herkomst.
    public var origins: Set<DependencyOrigin> = []
    /// nil is elke status.
    public var status: Status?

    public init(origins: Set<DependencyOrigin> = [], status: Status? = nil) {
        self.origins = origins
        self.status = status
    }

    public var isActive: Bool { !origins.isEmpty || status != nil }

    public func matches(_ row: RepoPackageRow, text: String = "") -> Bool {
        if !origins.isEmpty && !origins.contains(row.origin) { return false }
        switch status {
        case .hasUpdate?: if !row.hasUpdate { return false }
        case .category(let category)?: if row.category != category { return false }
        case nil: break
        }
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return ([row.name, row.workspace] + row.installedVersions + row.package.installs.flatMap(\.via))
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

/// De packages van één workspace in de tabel.
public struct RepoPackageGroup: Hashable, Sendable, Identifiable {
    public let workspace: String
    public let rows: [RepoPackageRow]

    public init(workspace: String, rows: [RepoPackageRow]) {
        self.workspace = workspace
        self.rows = rows
    }

    public var id: String { workspace }
}

extension RepoVersions {
    /// Elk package per workspace (de root eerst) als rij, met `latest` (op `PackageUse.key`) en
    /// de blokkades uit `context`.
    public func packageGroups(latest: (String) -> String?, context: UpdateContext = .empty) -> [RepoPackageGroup] {
        packageWorkspaces.filter { !$0.isEmpty }.map { workspace in
            let rows = [
                (DependencyOrigin.direct, workspace.direct), (.transitive, workspace.transitive),
                (.unknown, workspace.unknown), (.dev, workspace.dev),
            ].flatMap { origin, packages in
                packages.map { RepoPackageRow(package: $0, workspace: workspace.workspace, origin: origin, latest: latest($0.id), context: context) }
            }
            return RepoPackageGroup(workspace: workspace.workspace, rows: rows)
        }
    }
}

// MARK: - Samenvatting

/// De tellingen bovenaan de repo-pagina, elk een filter.
public struct RepoCheckSummary: Hashable, Sendable {
    /// Adviezen (lek per package).
    public let vulnerabilities: Int
    /// Talen en frameworks die achterlopen of geen support meer hebben.
    public let outdated: Int
    /// Packages (per workspace) die je nu binnen het bereik kunt bijwerken.
    public let canUpdate: Int
    /// Packages die iets anders tegenhoudt.
    public let blocked: Int
    /// Open meldingen, geheimen en eigen adviezen van de dienst.
    public let securityFindings: Int
    /// De tag waarmee de controle vergelijkt; nil zonder (bruikbare) release.
    public let comparedWith: String?

    public init(versions: RepoVersions, packages: [RepoPackageGroup]) {
        vulnerabilities = versions.advisoryCount
        outdated = versions.outdatedComponents.count
        let rows = packages.flatMap(\.rows)
        canUpdate = rows.filter { $0.category == .canUpdateNow }.count
        blocked = rows.filter { $0.category == .blocked }.count
        securityFindings = versions.security.map { $0.alerts.count + ($0.secretCount ?? 0) + $0.advisories.count } ?? 0
        comparedWith = versions.release.flatMap { $0.error == nil ? $0.tag : nil }
    }
}

// MARK: - Beveiliging van de dienst

/// Eén vondst van de dienst zelf als rij in de tabel: een melding van code scanning of Advanced
/// Security, of een eigen gepubliceerd advies.
public enum SecurityFindingRow: Hashable, Sendable, Identifiable {
    case alert(SecurityAlert)
    case ownAdvisory(GitHubAdvisory)

    public var id: String {
        switch self {
        case .alert(let alert): "alert|\(alert.id)"
        case .ownAdvisory(let advisory): "advisory|\(advisory.ghsaId)"
        }
    }

    public var title: String {
        switch self {
        case .alert(let alert): alert.title
        case .ownAdvisory(let advisory): advisory.summary ?? advisory.ghsaId
        }
    }

    public var url: URL {
        switch self {
        case .alert(let alert): alert.url
        case .ownAdvisory(let advisory): advisory.url
        }
    }

    /// Bij een melding zonder beveiligingsernst telt die van de tool (fout als gemiddeld).
    public var severityRank: Int {
        switch self {
        case .alert(let alert): alert.severityRank
        case .ownAdvisory(let advisory): SeverityLevel(advisory.severity).rawValue
        }
    }

    public var titleSortKey: String { title.lowercased() }
    /// "src/db.js:42", het package, of de geraakte packages van een eigen advies.
    public var placeSortKey: String {
        switch self {
        case .alert(let alert): alert.path.map { "\($0):\(alert.line ?? 0)" } ?? alert.package ?? ""
        case .ownAdvisory(let advisory): advisory.packages.map(\.name).joined(separator: ", ")
        }
    }
}

extension SecurityScan {
    /// Meldingen (ernstigste eerst) en daarna eigen adviezen (nieuwste eerst).
    public var findingRows: [SecurityFindingRow] {
        alerts.map(SecurityFindingRow.alert) + advisories.map(SecurityFindingRow.ownAdvisory)
    }
}
