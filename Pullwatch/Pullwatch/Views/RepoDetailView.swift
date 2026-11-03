import AppKit
import PullwatchCore
import SwiftUI

/// De pagina van één repo. Bovenaan de tellingen (elk een filter), daaronder het gekozen
/// tabblad: Overzicht (status, PR's, activiteit, volgen), Controle (runtimes en kwetsbaarheden),
/// Packages en Beveiliging. Een gekozen rij toont zijn details in het inspectievenster rechts.
struct RepoDetailView: View {
    @Environment(AccountsModel.self) private var accounts
    @Environment(VersionsModel.self) private var versions
    @Environment(AppRouter.self) private var router
    let summary: RepoSummary

    @State private var page = RepoPage()
    /// Alleen de breedteklasse, niet de breedte: zo tekent de pagina niet bij elke pixel opnieuw
    /// tijdens het vergroten van het venster of het openen van het inspectievenster.
    @State private var tableWidth = TableWidth.wide

    private var account: Account? { accounts.config.accounts.first { $0.id == summary.accountId } }

    private var input: RepoPage.Input {
        RepoPage.Input(versions: summary.versions, gitHub: summary.advisories, checkedAt: versions.versionReport?.checkedAt)
    }

    var body: some View {
        let page = page
        let tab = router.repoTab
        let webPage = account?.repoWebURL(summary.repo)
        VStack(spacing: 0) {
            RepoTabPicker(tab: Bindable(router).repoTab)
            // De tellers filteren de check en de packages; op Overzicht en Beveiliging zeggen ze
            // niets over wat er staat, dus daar geen balk.
            if tab.showsCheckSummary, let counts = page.summary {
                RepoCheckSummaryBar(
                    summary: counts,
                    isActive: { page.isActive($0, tab: tab) },
                    apply: { router.repoTab = page.apply($0, tab: tab) }
                )
                Divider()
            }
            RepoTabContent(summary: summary, account: account, page: page, tab: tab, width: tableWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: TableWidth.self) { TableWidth($0.size.width) } action: { tableWidth = $0 }
        }
        .inspector(isPresented: Binding(get: { page.showsInspector && tab.hasTable }, set: { page.showsInspector = $0 })) {
            RepoInspector(summary: summary, page: page, tab: tab)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 420)
        }
        .searchable(text: Binding(get: { page.searchText }, set: { page.searchText = $0 }), prompt: Text(tab.searchPrompt))
        .navigationTitle(Text(verbatim: summary.shortName))
        .navigationSubtitle(Text(verbatim: summary.repo))
        .toolbar {
            RepoDetailToolbar(summary: summary, page: page, webPage: webPage)
        }
        .task(id: input) {
            let repoVersions = input.versions
            let context = repoVersions.map(versions.updateContext(for:)) ?? .empty
            // Alleen de nieuwste versies van de packages van deze repo, als waarde voor buiten de main actor.
            let keys = (repoVersions?.packages ?? []) + (repoVersions?.otherPackages ?? [])
            let latest = Dictionary(keys.compactMap { use in versions.latestVersion(of: use.key).map { (use.key, $0) } },
                                    uniquingKeysWith: { first, _ in first })
            await page.update(input, context: context, latest: latest)
        }
        .onChange(of: tab, initial: true) { _, tab in
            page.activeTab = tab
        }
        .onChange(of: page.searchText) { _, text in
            // Zoeken op het overzicht zoekt in de controle.
            if tab == .overview && !text.isEmpty { router.repoTab = .check }
        }
        .onChange(of: router.repoSelectionRequest, initial: true) { _, request in
            guard let request else { return }
            router.repoTab = request.tab
            page.select(request)
            router.repoSelectionRequest = nil
        }
        .focusedSceneValue(\.browserTarget, webPage.map(BrowserTarget.page))
        .focusedSceneValue(\.repoTarget, RepoTarget(id: summary.id, isOpen: true))
    }
}

/// De tabbladen van de pagina, bovenaan in het midden.
private struct RepoTabPicker: View {
    @Binding var tab: RepoTab

    var body: some View {
        Picker("Tabblad", selection: $tab) {
            ForEach(RepoTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Kies wat de pagina van deze repo toont")
        .padding(.top, 10)
        .padding(.horizontal, 16)
    }
}

/// Het gekozen tabblad.
private struct RepoTabContent: View {
    @Environment(VersionsModel.self) private var versions
    let summary: RepoSummary
    let account: Account?
    let page: RepoPage
    let tab: RepoTab
    let width: TableWidth

    var body: some View {
        VStack(spacing: 0) {
            switch tab {
            case .overview:
                RepoOverviewTab(summary: summary, account: account)
            case .check:
                RepoCheckTab(
                    versions: summary.versions, page: page, width: width, isChecking: versions.versionCheck != nil,
                    openAdvisory: { NSWorkspace.shared.open($0.pageURL) }
                )
            case .packages:
                RepoPackagesTab(versions: summary.versions, page: page, width: width, isChecking: versions.versionCheck != nil)
            case .security:
                RepoSecurityTab(scan: summary.versions?.security, provider: account?.kind ?? .gitHub, page: page, width: width)
            }
        }
    }
}

// MARK: - Overzicht

private struct RepoOverviewTab: View {
    @Environment(AppModel.self) private var app
    @Environment(HistoryModel.self) private var historyModel
    @Environment(VersionsModel.self) private var versions
    @Environment(AppRouter.self) private var router
    let summary: RepoSummary
    let account: Account?

    private var historyRepo: HistoryRepo { HistoryRepo(accountId: summary.accountId, repo: summary.repo) }

    /// Open eerst, daarna de rest op volgorde van binnenkomst; hoogstens tien.
    private var pullRequests: [HistoryItem] {
        let items = historyModel.history.items.filter {
            $0.entry.kind == .pullRequest && $0.entry.accountId == summary.accountId
                && $0.entry.repo.caseInsensitiveCompare(summary.repo) == .orderedSame
        }
        return Array((items.filter { $0.entry.prState == .open } + items.filter { $0.entry.prState != .open }).prefix(10))
    }

    var body: some View {
        Form {
            RepoOverviewSection(
                health: summary.health,
                accountName: account?.displayName,
                latestTag: summary.latestTag,
                checkedAt: summary.versions == nil ? nil : versions.versionReport?.checkedAt
            )
            RepoPullRequestsSection(
                items: pullRequests,
                openCount: summary.openPullRequests,
                open: { historyModel.open($0) },
                showAll: { router.showHistory($0, repo: historyRepo) }
            )
            Section("PR's per maand") {
                ActivityChart(
                    stats: historyModel.activityStats(period: .month, filter: ActivityFilter(repoId: summary.id)),
                    period: .month
                )
                .frame(height: 140)
                .padding(.vertical, 4)
            }
            if let account {
                RepoWatchSection(watch: Bindable(app)[watch: summary.repo, account: account.id])
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Controle

/// Runtimes en frameworks als raster, meldingen over wat niet te checken was, en de
/// kwetsbaarheden als tabel.
private struct RepoCheckTab: View {
    let versions: RepoVersions?
    let page: RepoPage
    let width: TableWidth
    let isChecking: Bool
    let openAdvisory: (VulnerabilityRow) -> Void

    var body: some View {
        if let versions {
            if let error = versions.error {
                ContentUnavailableView("Check mislukt", systemImage: "exclamationmark.triangle", description: Text(verbatim: error))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    RepoComponentsArea(versions: versions, onlyOutdated: page.onlyOutdatedComponents, outdated: page.outdatedComponents)
                    Divider()
                    RepoVulnerabilitiesArea(versions: versions, page: page, width: width, openAdvisory: openAdvisory)
                }
            }
        } else {
            NotCheckedView(isChecking: isChecking)
        }
    }
}

/// Het raster met talen en frameworks, en wat er niet te checken was.
private struct RepoComponentsArea: View {
    let versions: RepoVersions
    let onlyOutdated: Bool
    let outdated: [ComponentVersion]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if versions.components.isEmpty {
                Text("Geen talen of frameworks herkend").foregroundStyle(.secondary)
            } else {
                ComponentGrid(components: onlyOutdated ? outdated : versions.components, release: versions.release)
            }
            if let release = versions.release, let error = release.error {
                CheckNotice(text: Text("Tag \(release.tag) niet te checken: \(error)", comment: "Tagnaam, foutmelding"))
            }
            if let vulnerabilityError = versions.vulnerabilityError {
                CheckNotice(text: Text(verbatim: vulnerabilityError))
            }
            if !versions.withdrawnVulnerabilities.isEmpty {
                WithdrawnAdvisoriesNote(vulnerabilities: versions.withdrawnVulnerabilities)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// Een melding over wat niet te checken was.
private struct CheckNotice: View {
    let text: Text

    var body: some View {
        Label {
            text.fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}

private struct RepoVulnerabilitiesArea: View {
    let versions: RepoVersions
    @Bindable var page: RepoPage
    let width: TableWidth
    let openAdvisory: (VulnerabilityRow) -> Void

    var body: some View {
        if !page.isBuilt {
            // De rijen worden nog opgebouwd (een fractie van een seconde); geen lege staat tonen.
            Color.clear
        } else if page.vulnerabilityCount == 0 {
            ContentUnavailableView(
                "Geen bekende kwetsbaarheden",
                systemImage: "checkmark.shield",
                description: Text("OSV.dev kent geen lekken in de packages van deze repo.")
            )
        } else {
            // Een andere breedte is een nieuwe tabel: de kolommen beginnen dan weer op hun ideale breedte.
            VulnerabilityTable(page: page, releaseTag: page.summary?.comparedWith, width: width, openAdvisory: openAdvisory)
                .id(width)
                .overlay {
                    if page.visibleVulnerabilities.isEmpty {
                        FilteredEmptyView(searchText: page.searchText) {
                            page.vulnerabilityFilter = VulnerabilityFilter()
                            page.searchText = ""
                        }
                    }
                }
        }
    }
}

/// Niets te zien door een filter of zoekterm, met een knop om ze te wissen.
private struct FilteredEmptyView: View {
    let searchText: String
    let clear: () -> Void

    var body: some View {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView {
                Label("Niets met dit filter", systemImage: "line.3.horizontal.decrease.circle")
            } actions: {
                Button("Wis filters", action: clear)
            }
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }
}

private struct NotCheckedView: View {
    let isChecking: Bool

    var body: some View {
        // De voortgang staat in de balk onderin; hier alleen wat er gebeurt.
        ContentUnavailableView(
            isChecking ? "Repo checken…" : "Nog niet gecheckt",
            systemImage: "checkmark.shield",
            description: Text("Check deze repo om de runtimes, packages en kwetsbaarheden te zien.")
        )
    }
}

// MARK: - Packages

private struct RepoPackagesTab: View {
    let versions: RepoVersions?
    @Bindable var page: RepoPage
    let width: TableWidth
    let isChecking: Bool

    var body: some View {
        if versions == nil {
            NotCheckedView(isChecking: isChecking)
        } else if !page.isBuilt {
            Color.clear
        } else if page.packageCount == 0 {
            ContentUnavailableView(
                "Geen packages",
                systemImage: "shippingbox",
                description: Text("Geen packages met een vaste versie gevonden")
            )
        } else {
            RepoPackageTable(page: page, width: width)
                .id(width)
                .overlay {
                    if page.visiblePackageGroups.isEmpty {
                        FilteredEmptyView(searchText: page.searchText) {
                            page.packageFilter = PackageFilter()
                            page.searchText = ""
                        }
                    }
                }
        }
    }
}

// MARK: - Beveiliging

private struct RepoSecurityTab: View {
    let scan: SecurityScan?
    @Bindable var page: RepoPage
    let provider: ProviderKind
    let width: TableWidth

    init(scan: SecurityScan?, provider: ProviderKind, page: RepoPage, width: TableWidth) {
        self.scan = scan
        self.provider = provider
        self.page = page
        self.width = width
    }

    var body: some View {
        if let scan {
            VStack(alignment: .leading, spacing: 0) {
                SecurityFeedGrid(scan: scan, provider: provider)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider()
                if !page.isBuilt {
                    Color.clear
                } else if page.securityCount == 0 {
                    ContentUnavailableView(
                        "Geen open meldingen",
                        systemImage: "checkmark.shield",
                        description: provider == .gitHub
                            ? Text("Code scanning en de eigen adviezen van deze repository melden niets.")
                            : Text("Advanced Security meldt niets voor deze repository.")
                    )
                } else {
                    SecurityFindingTable(page: page, width: width)
                        .id(width)
                        .overlay {
                            if page.visibleSecurity.isEmpty {
                                ContentUnavailableView.search(text: page.searchText)
                            }
                        }
                }
            }
        } else {
            ContentUnavailableView(
                "Geen beveiligingsgegevens",
                systemImage: "lock.shield",
                description: Text("De dienst geeft voor deze repository geen code scanning, geheimen of eigen adviezen.")
            )
        }
    }
}

// MARK: - Inspectievenster

private struct RepoInspector: View {
    @Environment(VersionsModel.self) private var versions
    @Environment(AppRouter.self) private var router
    let summary: RepoSummary
    let page: RepoPage
    let tab: RepoTab

    var body: some View {
        VStack(spacing: 0) {
            switch tab {
            case .check:
                if let selected = page.selectedVulnerability {
                    AdvisoryInspector(
                        row: selected.row,
                        install: selected.install,
                        releaseTag: page.summary?.comparedWith,
                        showsWorkspace: page.vulnerabilitiesSpanWorkspaces,
                        showPackage: versions.packageSummaries.contains { $0.label == selected.row.package } ? { router.showPackage($0) } : nil
                    )
                } else {
                    NoSelectionView(text: Text("Kies een kwetsbaarheid om de details te zien."))
                }
            case .packages:
                if let selected = page.selectedPackage {
                    PackageInspector(
                        row: selected,
                        showsWorkspace: page.packagesSpanWorkspaces,
                        showPackage: versions.packageSummaries.contains { $0.id == selected.row.package.id } ? { router.showPackage($0) } : nil
                    )
                } else {
                    NoSelectionView(text: Text("Kies een package om de details te zien."))
                }
            case .security:
                if let selected = page.selectedSecurityFinding {
                    SecurityFindingInspector(row: selected)
                } else {
                    NoSelectionView(text: Text("Kies een melding om de details te zien."))
                }
            case .overview:
                EmptyView()
            }
        }
    }
}

private struct NoSelectionView: View {
    let text: Text

    var body: some View {
        ContentUnavailableView {
            Label("Niets gekozen", systemImage: "sidebar.trailing")
        } description: {
            text
        }
    }
}

// MARK: - Knoppenbalk

/// Filter, inspectievenster, opnieuw checken en de rest. Het tabblad staat bovenaan de pagina
/// zelf, zodat deze knoppen ook in het kleinste venster zichtbaar blijven.
private struct RepoDetailToolbar: ToolbarContent {
    @Environment(VersionsModel.self) private var versions
    @Environment(AppRouter.self) private var router
    let summary: RepoSummary
    let page: RepoPage
    let webPage: URL?

    var body: some ToolbarContent {
        ToolbarItemGroup {
            RepoFilterMenu(page: page, tab: router.repoTab)
            Button {
                page.showsInspector.toggle()
            } label: {
                Label("Inspectievenster", systemImage: "sidebar.trailing")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(!router.repoTab.hasTable)
            .help("Toon of verberg de details van de gekozen rij (spatie)")
            Button {
                versions.startRefresh(of: summary)
            } label: {
                Label("Check", systemImage: "arrow.clockwise")
            }
            .disabled(versions.versionCheck != nil || versions.versionReport == nil || !versions.refreshingRepos.isEmpty)
            .help(versions.versionReport == nil ? Text("Check eerst alle repo's") : Text("Check deze repo opnieuw"))
            Menu {
                if let webPage {
                    Button("Open in browser") { NSWorkspace.shared.open(webPage) }
                }
                Button("Statistieken") { router.showStats(repoId: summary.id) }
                if let repoVersions = summary.versions {
                    Button("Kopieer alles") {
                        Pasteboard.copy(repoVersions.clipboardText(advisories: summary.advisories, report: versions.versionReport))
                    }
                    .help("Kopieer de afhankelijkheden en kwetsbaarheden van deze repo naar het klembord")
                }
            } label: {
                Label("Meer", systemImage: "ellipsis.circle")
            }
            .help("Open in browser, statistieken en kopiëren")
        }
    }
}

/// Het filter van het gekozen tabblad: voor de controle ernst, herkomst, met oplossing en in de
/// release; voor de packages status en herkomst.
private struct RepoFilterMenu: View {
    @Bindable var page: RepoPage
    let tab: RepoTab

    private var isActive: Bool {
        switch tab {
        case .check: page.vulnerabilityFilter.isActive || page.onlyOutdatedComponents
        case .packages: page.packageFilter.isActive
        case .overview, .security: false
        }
    }

    var body: some View {
        Menu {
            switch tab {
            case .check:
                VulnerabilityFilterItems(filter: $page.vulnerabilityFilter, onlyOutdated: $page.onlyOutdatedComponents,
                                         releaseTag: page.summary?.comparedWith)
            case .packages:
                PackageFilterItems(filter: $page.packageFilter)
            case .overview, .security:
                EmptyView()
            }
        } label: {
            Label("Filter", systemImage: isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .disabled(tab == .overview || tab == .security)
        .help("Filter de tabel")
    }
}

private struct VulnerabilityFilterItems: View {
    @Binding var filter: VulnerabilityFilter
    @Binding var onlyOutdated: Bool
    let releaseTag: String?

    var body: some View {
        Section("Ernst") {
            ForEach(SeverityLevel.allCases.reversed(), id: \.self) { level in
                Toggle(isOn: $filter.severities[contains: level]) { Text(level.label) }
            }
        }
        Section("Herkomst") {
            ForEach(DependencyOrigin.allCases, id: \.self) { origin in
                Toggle(isOn: $filter.origins[contains: origin]) { Text(origin.title) }
            }
        }
        Section {
            Toggle("Met oplossing", isOn: $filter.onlyWithFix)
            if let releaseTag {
                Toggle(isOn: $filter.onlyInRelease) { Text("Ook in \(releaseTag)", comment: "Tagnaam") }
            }
            Toggle("Alleen verouderde runtimes", isOn: $onlyOutdated)
        }
        Button("Wis filters") {
            filter = VulnerabilityFilter()
            onlyOutdated = false
        }
        .disabled(!filter.isActive && !onlyOutdated)
    }
}

private struct PackageFilterItems: View {
    @Binding var filter: PackageFilter

    var body: some View {
        Picker("Status", selection: $filter.status) {
            Text("Elke status").tag(PackageFilter.Status?.none)
            Text("Met nieuwere versie").tag(PackageFilter.Status?.some(.hasUpdate))
            ForEach([UpdateCategory.canUpdateNow, .needsManifestChange, .blocked], id: \.self) { category in
                Text(category.title).tag(PackageFilter.Status?.some(.category(category)))
            }
        }
        .pickerStyle(.inline)
        Section("Herkomst") {
            ForEach(DependencyOrigin.allCases, id: \.self) { origin in
                Toggle(isOn: $filter.origins[contains: origin]) { Text(origin.title) }
            }
        }
        Button("Wis filters") { filter = PackageFilter() }
            .disabled(!filter.isActive)
    }
}

extension DependencyOrigin {
    var title: LocalizedStringResource {
        switch self {
        case .direct: "Direct"
        case .transitive: "Transitief"
        case .unknown: "Herkomst onbekend"
        case .dev: "Alleen dev"
        }
    }
}

extension RepoTab {
    var searchPrompt: LocalizedStringResource {
        switch self {
        case .overview, .check: "Zoek op CVE, package of versie…"
        case .packages: "Zoek op package of versie…"
        case .security: "Zoek op titel of bestand…"
        }
    }
}

extension Set {
    /// Een element aan of uit, als binding voor een schakelaar.
    subscript(contains element: Element) -> Bool {
        get { contains(element) }
        set {
            if newValue { insert(element) } else { remove(element) }
        }
    }
}
