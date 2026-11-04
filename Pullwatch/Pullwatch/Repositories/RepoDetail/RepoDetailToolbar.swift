import AppKit
import PullwatchCore
import SwiftUI

/// Filter, inspectievenster, opnieuw checken en de rest. Het tabblad staat bovenaan de pagina
/// zelf, zodat deze knoppen ook in het kleinste venster zichtbaar blijven.
struct RepoDetailToolbar: ToolbarContent {
    @Environment(AccountsModel.self) private var accounts
    @Environment(HistoryModel.self) private var historyModel
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
                        Pasteboard.copy(repoVersions.clipboardText(
                            advisories: summary.advisories, report: versions.versionReport,
                            advisoryDetailsOff: !accounts.config.isEnabled(.gitHubAdvisoryDatabase)
                        ))
                    }
                    .help("Kopieer de afhankelijkheden en kwetsbaarheden van deze repo naar het klembord")
                }
                AgentBriefMenu(briefs: RepoBriefs(
                    summary: summary, account: accounts.config.accounts.first { $0.id == summary.accountId },
                    accounts: accounts, versions: versions, history: historyModel
                ))
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

/// De filters op kwetsbaarheden in het filtermenu: ernst, herkomst, met oplossing en in de release.
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

/// De filters op packages in het filtermenu: status en herkomst.
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

extension Set {
    /// Een element aan of uit, als binding voor een schakelaar.
    subscript(contains element: Element) -> Bool {
        get { contains(element) }
        set {
            if newValue { insert(element) } else { remove(element) }
        }
    }
}
