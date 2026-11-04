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
        .searchable(text: Bindable(page).searchText, prompt: Text(tab.searchPrompt))
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
    @Environment(AccountsModel.self) private var accounts
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
                    advisoryDetailsOff: !accounts.config.isEnabled(.gitHubAdvisoryDatabase),
                    openAdvisory: { NSWorkspace.shared.open($0.pageURL) }
                )
            case .packages:
                RepoPackagesTab(versions: summary.versions, page: page, width: width, isChecking: versions.versionCheck != nil)
            case .security:
                RepoSecurityTab(
                    scan: summary.versions?.security, skipped: summary.versions?.skippedSecuritySource,
                    provider: account?.kind ?? .gitHub, page: page, width: width
                )
            }
        }
    }
}

// MARK: - Knoppenbalk

extension RepoTab {
    var searchPrompt: LocalizedStringResource {
        switch self {
        case .overview, .check: "Zoek op CVE, package of versie…"
        case .packages: "Zoek op package of versie…"
        case .security: "Zoek op titel of bestand…"
        }
    }
}
