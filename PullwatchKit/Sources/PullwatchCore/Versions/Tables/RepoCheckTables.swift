import Foundation

// De rijen, filters en tellingen van de controle op de repo-pagina: één rij per advies, één rij per
// package per workspace, en de samenvatting bovenaan. De views tonen alleen wat hier staat.

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
    let securityFindings: Int
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

    public var titleSortKey: TextSortKey { TextSortKey(title) }
    /// "src/db.js:42", het package, of de geraakte packages van een eigen advies.
    public var placeSortKey: TextSortKey { TextSortKey(place) }

    public var place: String {
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

// MARK: - Alles samen

/// De rijen en tellingen van één repo-pagina, in één keer opgebouwd. Bij een repo met duizenden
/// packages kost dat merkbaar tijd; het is `Sendable`, zodat de app het buiten de main actor bouwt.
public struct RepoCheckTables: Sendable {
    public let vulnerabilities: [VulnerabilityRow]
    public let packages: [RepoPackageGroup]
    public let security: [SecurityFindingRow]
    public let outdatedComponents: [ComponentVersion]
    public let summary: RepoCheckSummary
    /// Of de kwetsbaarheden en de packages meer dan één workspace beslaan.
    public let vulnerabilitiesSpanWorkspaces: Bool
    public let packagesSpanWorkspaces: Bool

    /// `latest` is de nieuwste versie per `PackageUse.key`.
    public init(versions: RepoVersions, gitHub: [String: GitHubAdvisory], context: UpdateContext, latest: [String: String]) {
        vulnerabilities = versions.vulnerabilityRows(gitHub: gitHub, context: context)
        packages = versions.packageGroups(latest: { latest[$0] }, context: context)
        security = versions.security?.findingRows ?? []
        outdatedComponents = versions.outdatedComponents
        summary = RepoCheckSummary(versions: versions, packages: packages)
        vulnerabilitiesSpanWorkspaces = Set(versions.vulnerabilities.map(\.workspace)).count > 1
        packagesSpanWorkspaces = packages.count > 1
    }

    /// Bouwt de tabellen buiten de actor van de aanroeper.
    @concurrent
    public static func build(versions: RepoVersions, gitHub: [String: GitHubAdvisory], context: UpdateContext, latest: [String: String]) async -> RepoCheckTables {
        RepoCheckTables(versions: versions, gitHub: gitHub, context: context, latest: latest)
    }
}
