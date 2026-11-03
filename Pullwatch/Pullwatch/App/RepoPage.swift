import Foundation
import PullwatchCore

/// De staat van één geopende repo-pagina: de rijen van de tabellen (één keer opgebouwd per
/// rapport), de filters, de zoekterm, de sortering en de selectie per tabblad. Wat zichtbaar is
/// wordt alleen opnieuw berekend als een van die dingen verandert, zodat de views alleen tekenen.
@Observable
final class RepoPage {
    /// De invoer: alles wat de tabellen nodig hebben uit het rapport.
    struct Input: Equatable {
        let versions: RepoVersions?
        let gitHub: [String: GitHubAdvisory]
        let checkedAt: Date?
    }

    private(set) var summary: RepoCheckSummary?
    private(set) var outdatedComponents: [ComponentVersion] = []
    /// Of de workspaces van de kwetsbaarheden meer dan één map beslaan.
    private(set) var vulnerabilitiesSpanWorkspaces = false
    private(set) var packagesSpanWorkspaces = false

    private var vulnerabilityRows: [VulnerabilityRow] = []
    private var packageGroups: [RepoPackageGroup] = []
    private var securityRows: [SecurityFindingRow] = []

    private(set) var visibleVulnerabilities: [VulnerabilityTableRow] = []
    private(set) var visiblePackageGroups: [RepoPackageGroup] = []
    private(set) var visibleSecurity: [SecurityFindingRow] = []

    /// Aantal rijen zonder filter of zoekterm, voor de lege staat.
    var vulnerabilityCount: Int { vulnerabilityRows.count }
    var packageCount: Int { packageGroups.reduce(0) { $0 + $1.rows.count } }
    var securityCount: Int { securityRows.count }

    var searchText = "" { didSet { if searchText != oldValue { recomputeVisible() } } }
    var vulnerabilityFilter = VulnerabilityFilter() { didSet { recomputeVulnerabilities() } }
    var packageFilter = PackageFilter() { didSet { recomputePackages() } }
    /// Alleen de talen en frameworks die achterlopen (het filter "Verouderd").
    var onlyOutdatedComponents = false

    var vulnerabilitySort = [KeyPathComparator(\VulnerabilityTableRow.severitySortKey, order: .reverse)] {
        didSet { recomputeVulnerabilities() }
    }
    var packageSort = [KeyPathComparator(\RepoPackageTableRow.statusSortKey), KeyPathComparator(\RepoPackageTableRow.nameSortKey)] {
        didSet { recomputePackages() }
    }
    var securitySort = [KeyPathComparator(\SecurityFindingRow.severityRank, order: .reverse)] {
        didSet { recomputeSecurity() }
    }

    var vulnerabilitySelection: VulnerabilityTableRow.ID?
    var packageSelection: RepoPackageTableRow.ID?
    var securitySelection: SecurityFindingRow.ID?
    var showsInspector = false
    /// Opengeklapte rijen met meer installs.
    var expanded: Set<String> = []

    /// Of de rijen voor deze invoer er al zijn; tot dan toont de pagina een lege tabel.
    private(set) var isBuilt = false

    /// Bouwt de rijen opnieuw op uit het rapport, buiten de main actor (bij een grote monorepo
    /// kost dat merkbaar tijd), en zet ze daarna in één keer neer.
    func update(_ input: Input, context: UpdateContext, latest: [String: String]) async {
        guard let versions = input.versions, versions.error == nil else {
            apply(nil)
            return
        }
        let tables = await RepoCheckTables.build(versions: versions, gitHub: input.gitHub, context: context, latest: latest)
        guard !Task.isCancelled else { return }
        apply(tables)
    }

    private func apply(_ tables: RepoCheckTables?) {
        summary = tables?.summary
        outdatedComponents = tables?.outdatedComponents ?? []
        vulnerabilityRows = tables?.vulnerabilities ?? []
        packageGroups = tables?.packages ?? []
        securityRows = tables?.security ?? []
        vulnerabilitiesSpanWorkspaces = tables?.vulnerabilitiesSpanWorkspaces ?? false
        packagesSpanWorkspaces = tables?.packagesSpanWorkspaces ?? false
        #if DEBUG
        // Voor de foto's: elke rij met installs eronder staat open.
        if SnapshotCamera.expandsAll {
            expanded = Set(vulnerabilityRows.filter { $0.advisory.installs.count > 1 }.map(\.id)
                           + packageGroups.flatMap(\.rows).filter { $0.package.installs.count > 1 }.map(\.id))
        }
        #endif
        isBuilt = true
        recomputeVisible()
    }

    /// Het tabblad dat de pagina toont: zoeken en sorteren rekent alleen dat tabblad door.
    var activeTab: RepoTab = .overview {
        didSet { if activeTab != oldValue { recomputeVisible() } }
    }

    // MARK: Selectie

    /// Het geselecteerde advies, ook als een install eronder gekozen is.
    var selectedVulnerability: VulnerabilityTableRow? {
        guard let id = vulnerabilitySelection else { return nil }
        return visibleVulnerabilities.lazy.flatMap { [$0] + $0.children }.first { $0.id == id }
    }

    var selectedPackage: RepoPackageTableRow? {
        guard let id = packageSelection else { return nil }
        return visiblePackageGroups.lazy.flatMap(\.rows).map { RepoPackageTableRow(row: $0) }
            .flatMap { [$0] + $0.children }.first { $0.id == id }
    }

    var selectedSecurityFinding: SecurityFindingRow? {
        guard let id = securitySelection else { return nil }
        return visibleSecurity.first { $0.id == id }
    }

    /// Kiest een rij in `tab` en opent het inspectievenster; met meer installs klapt het advies open.
    func select(_ request: RepoSelectionRequest) {
        guard request.rowId != nil else {
            showsInspector = false
            return
        }
        switch request.tab {
        case .check: vulnerabilitySelection = request.rowId
        case .packages: packageSelection = request.rowId
        case .security: securitySelection = request.rowId
        case .overview: return
        }
        showsInspector = true
    }

    // MARK: Filters vanuit de samenvatting

    enum SummaryFilter: Hashable {
        case vulnerabilities, outdated, canUpdate, blocked, security
    }

    /// Of een teller in de samenvatting nu als filter aan staat.
    func isActive(_ filter: SummaryFilter, tab: RepoTab) -> Bool {
        switch filter {
        case .vulnerabilities: tab == .check && !onlyOutdatedComponents
        case .outdated: tab == .check && onlyOutdatedComponents
        case .canUpdate: tab == .packages && packageFilter.status == .category(.canUpdateNow)
        case .blocked: tab == .packages && packageFilter.status == .category(.blocked)
        case .security: tab == .security
        }
    }

    /// Zet het filter van een teller en geeft het tabblad terug waar het hoort; nog eens klikken
    /// zet het filter weer uit.
    func apply(_ filter: SummaryFilter, tab: RepoTab) -> RepoTab {
        let wasActive = isActive(filter, tab: tab)
        switch filter {
        case .vulnerabilities:
            onlyOutdatedComponents = false
            vulnerabilityFilter = VulnerabilityFilter()
            return .check
        case .outdated:
            onlyOutdatedComponents = !wasActive
            return .check
        case .canUpdate:
            packageFilter.status = wasActive ? nil : .category(.canUpdateNow)
            return .packages
        case .blocked:
            packageFilter.status = wasActive ? nil : .category(.blocked)
            return .packages
        case .security:
            return .security
        }
    }

    // MARK: Herberekenen

    /// Alleen het zichtbare tabblad; een ander tabblad rekent zichzelf door als het zichtbaar wordt.
    private func recomputeVisible() {
        switch activeTab {
        case .overview: break
        case .check: recomputeVulnerabilities()
        case .packages: recomputePackages()
        case .security: recomputeSecurity()
        }
    }

    private func recomputeVulnerabilities() {
        visibleVulnerabilities = vulnerabilityRows.filter { vulnerabilityFilter.matches($0, text: searchText) }
            .map { VulnerabilityTableRow(row: $0) }
            .sorted(using: vulnerabilitySort)
    }

    private func recomputePackages() {
        visiblePackageGroups = packageGroups.compactMap { group in
            let rows = group.rows.filter { packageFilter.matches($0, text: searchText) }
                .map { RepoPackageTableRow(row: $0) }
                .sorted(using: packageSort)
                .map(\.row)
            return rows.isEmpty ? nil : RepoPackageGroup(workspace: group.workspace, rows: rows)
        }
    }

    private func recomputeSecurity() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        visibleSecurity = securityRows.filter { row in
            query.isEmpty || row.title.localizedCaseInsensitiveContains(query) || row.place.localizedCaseInsensitiveContains(query)
        }
        .sorted(using: securitySort)
    }
}
