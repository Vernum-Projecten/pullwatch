import AppKit
import PullwatchCore
import SwiftUI

// Waarden voor sorteren en tonen, geen UI-state: buiten de main actor bruikbaar (KeyPathComparator).
nonisolated extension RepoHealth {
    var color: Color {
        switch self {
        case .problem: .red
        case .behind: .orange
        case .ok: .green
        case .unknown: .secondary
        }
    }

    /// Elke stand een eigen vorm, zodat de kleur niet de enige aanwijzing is.
    var symbol: String {
        switch self {
        case .problem: "xmark.octagon.fill"
        case .behind: "exclamationmark.triangle.fill"
        case .ok: "checkmark.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .problem: "Probleem"
        case .behind: "Loopt achter"
        case .ok: "Actueel"
        case .unknown: "Onbekend"
        }
    }

    /// Slechtste eerst bij oplopend sorteren.
    var sortRank: Int {
        switch self {
        case .problem: 0
        case .behind: 1
        case .unknown: 2
        case .ok: 3
        }
    }
}

// Waarden voor sorteren en tonen, geen UI-state: buiten de main actor bruikbaar (KeyPathComparator).
nonisolated extension RepoSummary {
    var healthRank: Int { health.sortRank }
    /// Zonder tag achteraan.
    var latestTagSortKey: String { latestTag ?? "\u{10FFFF}" }
    /// Repo-naam zonder project of eigenaar ervoor.
    var shortName: String { String(repo.split(separator: "/", maxSplits: 1).last ?? Substring(repo)) }
}

/// Het teken voor hoe een repo ervoor staat, met een toegankelijk label.
struct HealthIcon: View {
    let health: RepoHealth

    var body: some View {
        Image(systemName: health.symbol)
            .foregroundStyle(health.color)
            .accessibilityLabel(Text(health.label))
            .help(Text(health.label))
    }
}

/// Gevolgde repo's in een tabel, slechtste eerst; dubbelklik of Return opent de pagina van de repo.
struct ReposView: View {
    let model: AppModel
    /// Alleen dit project (uit de zijbalk); nil voor alles.
    var group: HistoryGroup.ID? = nil
    var groupName: String? = nil

    @State private var searchText = ""
    @State private var selection: RepoSummary.ID?
    @State private var sortOrder = [KeyPathComparator(\RepoSummary.healthRank), KeyPathComparator(\RepoSummary.repo)]
    @State private var rows: [RepoSummary] = []

    private struct Query: Equatable {
        let text: String
        let sortOrder: [KeyPathComparator<RepoSummary>]
        let summaries: [RepoSummary]
    }

    private func recompute() {
        let all = model.repoSummaries.filter { group == nil || $0.group == group }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let found = query.isEmpty ? all : all.filter { summary in
            summary.repo.localizedCaseInsensitiveContains(query)
                || (summary.versions?.components.contains { $0.label.localizedCaseInsensitiveContains(query) } ?? false)
                || (summary.versions?.vulnerabilities.contains {
                    $0.package.localizedCaseInsensitiveContains(query) || ($0.cve ?? $0.id).localizedCaseInsensitiveContains(query)
                } ?? false)
        }
        rows = found.sorted(using: sortOrder)
    }

    private var selectedPage: URL? {
        guard let selection, let summary = model.repoSummariesById[selection] else { return nil }
        return model.config.accounts.first { $0.id == summary.accountId }?.repoWebURL(summary.repo)
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Status", value: \.healthRank) { summary in
                HealthIcon(health: summary.health)
            }
            .width(min: 56, ideal: 60)
            TableColumn("Repo", value: \.repo) { summary in
                Text(verbatim: group == nil ? summary.repo : summary.shortName)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .width(min: 140, ideal: 220)
            TableColumn("Bevindingen") { summary in
                RepoFindingsView(findings: RepoFinding.findings(for: summary))
            }
            .width(min: 160, ideal: 280)
            TableColumn("Open PR's", value: \.openPullRequests) { summary in
                Text(summary.openPullRequests, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(summary.openPullRequests == 0 ? .tertiary : .primary)
            }
            .width(min: 60, ideal: 70)
            TableColumn("Laatste tag", value: \.latestTagSortKey) { summary in
                if let tag = summary.latestTag {
                    Text(verbatim: tag).monospacedDigit().lineLimit(1)
                }
            }
            .width(min: 70, ideal: 100)
        }
        .contextMenu(forSelectionType: RepoSummary.ID.self) { ids in
            if let id = ids.first, let summary = model.repoSummariesById[id] {
                Button("Open de pagina van deze repo") { model.showRepo(id: id) }
                if let url = model.config.accounts.first(where: { $0.id == summary.accountId })?.repoWebURL(summary.repo) {
                    Button("Open in browser") { NSWorkspace.shared.open(url) }
                }
                Button("Check deze repo opnieuw") {
                    Task { await model.refreshVersions(of: summary) }
                }
                .disabled(model.versionCheck != nil || model.versionReport == nil)
            }
        } primaryAction: { ids in
            if let id = ids.first { model.showRepo(id: id) }
        }
        .overlay {
            if rows.isEmpty {
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty
                    && (model.isFillingHistory || model.versionCheck != nil) {
                    // De voortgang staat in de balk onderin; hier alleen wat er gebeurt.
                    ContentUnavailableView(
                        "Repo's ophalen…",
                        systemImage: "folder",
                        description: model.fillingAccountName.map {
                            Text("Pullwatch haalt de repo's op van \($0).", comment: "Accountnaam, bv. @octocat op GitHub")
                        } ?? Text("Pullwatch haalt de repo's op die je volgt.")
                    )
                } else if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView(
                        "Geen repo's",
                        systemImage: "folder",
                        description: Text("Volg repo's in Instellingen en check ze om hier te zien hoe ze ervoor staan.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .searchable(
            text: $searchText,
            prompt: groupName.map { Text("Zoek in \($0)…", comment: "Projectnaam") } ?? Text("Zoek op repo, taal of CVE…")
        )
        .searchShortcut()
        .navigationTitle(groupName.map { Text(verbatim: $0) } ?? Text("Repo's"))
        .navigationSubtitle(CheckedSubtitle.text(model.versionReport?.checkedAt))
        .toolbar {
            ToolbarItem {
                Button {
                    model.watchRepository()
                } label: {
                    Label("Volg een repository…", systemImage: "plus")
                }
                .disabled(model.accountsForExtraRepos.isEmpty)
                .help("Een losse repository volgen, ook een openbare van een andere organisatie")
            }
            CheckAllToolbarItem(model: model)
        }
        .onChange(of: Query(text: searchText, sortOrder: sortOrder, summaries: model.repoSummaries), initial: true) {
            recompute()
        }
        .focusedSceneValue(\.browserTarget, selectedPage.map(BrowserTarget.page))
        .focusedSceneValue(\.repoTarget, selection.map { RepoTarget(id: $0, isOpen: false) })
    }
}

/// "Gecheckt …" onder de titel, of dat er nog niet gecheckt is.
enum CheckedSubtitle {
    static func text(_ checkedAt: Date?) -> Text {
        guard let checkedAt else { return Text("Nog niet gecheckt") }
        return Text("Gecheckt \(checkedAt.formatted(date: .abbreviated, time: .shortened))")
    }
}

/// "Alles checken" in de knoppenbalk. De knop blijft staan (uitgeschakeld) terwijl een check
/// loopt; de voortgang staat in de balk onderin het venster.
struct CheckAllToolbarItem: ToolbarContent {
    let model: AppModel

    var body: some ToolbarContent {
        ToolbarItem {
            Button {
                Task { await model.checkVersions() }
            } label: {
                Label("Alles checken", systemImage: "checkmark.shield")
            }
            .disabled(model.versionCheck != nil || !model.refreshingRepos.isEmpty)
            .help("Leest per gevolgde repo de taal- en frameworkversies en vergelijkt ze met endoflife.date; packages gaan langs OSV.dev voor bekende CVE's en langs hun register voor de nieuwste versie")
        }
    }
}

/// Korte bevindingen in de tabel: CVE's, slechtste runtime, packages met een nieuwe versie.
enum RepoFinding: Hashable, Identifiable {
    case unchecked
    case failed
    case vulnerabilities(Int)
    /// Open critical- en high-meldingen van code scanning of Advanced Security.
    case securityAlerts(Int)
    case endOfLife(label: String, version: String)
    case runtimeBehind(label: String, version: String)
    case packageUpdates(Int)
    /// Een bron stond uit: over een deel van de repo zegt de check niets.
    case notChecked
    case current

    var id: Self { self }

    var text: LocalizedStringResource {
        switch self {
        case .unchecked: "nog niet gecheckt"
        case .failed: "check mislukt"
        case .vulnerabilities(let count): "\(count) CVE's"
        case .securityAlerts(let count): "\(count) open meldingen"
        case .endOfLife(let label, let version): "\(label) \(version) EOL"
        case .runtimeBehind(let label, let version): "\(label) \(version) achter"
        case .packageUpdates(let count): "\(count) nieuwe versies"
        case .notChecked: "niet alles gecontroleerd"
        case .current: "actueel"
        }
    }

    var tint: Color {
        switch self {
        case .unchecked, .failed, .notChecked: .secondary
        case .vulnerabilities, .securityAlerts, .endOfLife: .red
        case .runtimeBehind, .packageUpdates: .orange
        case .current: .green
        }
    }

    static func findings(for summary: RepoSummary) -> [RepoFinding] {
        guard let versions = summary.versions else { return [.unchecked] }
        if versions.error != nil { return [.failed] }
        var findings: [RepoFinding] = []
        if !versions.vulnerabilities.isEmpty { findings.append(.vulnerabilities(versions.advisoryCount)) }
        if !summary.seriousSecurityAlerts.isEmpty { findings.append(.securityAlerts(summary.seriousSecurityAlerts.count)) }
        if let worst = versions.components.filter({ $0.status == .eol || $0.status == .behind }).max(by: { $0.status < $1.status }) {
            findings.append(worst.status == .eol
                            ? .endOfLife(label: worst.label, version: worst.version)
                            : .runtimeBehind(label: worst.label, version: worst.version))
        }
        if !summary.packageUpdates.isEmpty { findings.append(.packageUpdates(summary.packageUpdates.count)) }
        if !versions.skippedSources.isEmpty { findings.append(.notChecked) }
        return findings.isEmpty ? [.current] : findings
    }
}

private struct RepoFindingsView: View {
    let findings: [RepoFinding]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(findings) { finding in
                Pill(text: finding.text, tint: finding.tint)
            }
        }
    }
}

// MARK: - Repo-pagina

/// Alles over één repo: overzicht, PR's, activiteit, controle, packages en volgen. Elke sectie
/// is een eigen view met alleen wat hij toont.
struct RepoDetailView: View {
    @Bindable var model: AppModel
    let summary: RepoSummary

    private var account: Account? { model.config.accounts.first { $0.id == summary.accountId } }

    private var historyRepo: HistoryRepo { HistoryRepo(accountId: summary.accountId, repo: summary.repo) }

    /// Open eerst, daarna de rest op volgorde van binnenkomst; hoogstens tien.
    private var pullRequests: [HistoryItem] {
        let items = model.history.items.filter {
            $0.entry.kind == .pullRequest && $0.entry.accountId == summary.accountId
                && $0.entry.repo.caseInsensitiveCompare(summary.repo) == .orderedSame
        }
        return Array((items.filter { $0.entry.prState == .open } + items.filter { $0.entry.prState != .open }).prefix(10))
    }

    /// De kop van een opdracht voor een AI-agent; `checkedAt` nil neemt de laatste versiecheck.
    private func briefRepository(page: URL?, checkedAt: Date? = nil) -> AgentBrief.Repository {
        AgentBrief.Repository(
            name: summary.repo, url: page,
            checkedAt: checkedAt ?? (summary.versions == nil ? nil : model.versionReport?.checkedAt)
        )
    }

    var body: some View {
        let page = account?.repoWebURL(summary.repo)
        Form {
            RepoOverviewSection(
                health: summary.health,
                accountName: account?.displayName,
                latestTag: summary.latestTag,
                checkedAt: summary.versions == nil ? nil : model.versionReport?.checkedAt
            )
            RepoPullRequestsSection(
                items: pullRequests,
                openCount: summary.openPullRequests,
                open: { model.open($0) },
                showAll: { model.showHistory($0, repo: historyRepo) },
                brief: {
                    AgentBrief.pullRequests(briefRepository(page: page, checkedAt: Date()), items: pullRequests, openCount: summary.openPullRequests)
                }
            )
            Section {
                ActivityChart(
                    stats: model.activityStats(period: .month, filter: ActivityFilter(repoId: summary.id)),
                    period: .month
                )
                .frame(height: 140)
                .padding(.vertical, 4)
            } header: {
                HStack {
                    Text("PR's per maand")
                    Spacer()
                    AgentBriefButton {
                        AgentBrief.pullRequestsPerMonth(
                            briefRepository(page: page, checkedAt: Date()),
                            stats: model.activityStats(period: .month, filter: ActivityFilter(repoId: summary.id))
                        )
                    }
                }
            }
            RepoControlSection(
                versions: summary.versions,
                gitHubAdvisories: summary.advisories,
                advisoryDetailsOff: !model.config.isEnabled(.gitHubAdvisoryDatabase),
                knownPackages: Set(model.packageSummaries.map(\.label)),
                showPackage: { model.showPackage($0) },
                brief: summary.versions.map { versions in
                    {
                        AgentBrief.vulnerabilities(
                            briefRepository(page: page), versions: versions, advisories: summary.advisories,
                            advisoryDetailsOff: !model.config.isEnabled(.gitHubAdvisoryDatabase),
                            context: model.visibleVersionReport?.updateContext(for: versions) ?? .empty
                        )
                    }
                }
            )
            let provider = account?.kind ?? .gitHub
            let securityBrief = {
                AgentBrief.security(
                    briefRepository(page: page), provider: provider, scan: summary.versions?.security,
                    skipped: summary.versions?.skippedSecuritySource
                )
            }
            if let security = summary.versions?.security {
                RepoSecuritySection(scan: security, provider: provider, brief: securityBrief)
            } else if let source = summary.versions?.skippedSecuritySource {
                Section {
                    SourceOffText(text: SourceOff.notChecked(source), isWarning: true)
                } header: {
                    HStack {
                        Text(source == .gitHubSecurity ? "Beveiliging op GitHub" : "Advanced Security")
                        Spacer()
                        AgentBriefButton(brief: securityBrief)
                    }
                }
            }
            RepoPackageUpdatesSection(
                updates: summary.packageUpdates, repoId: summary.id, isChecked: summary.versions != nil,
                skipped: summary.versions?.skippedVersionSources ?? [],
                brief: {
                    AgentBrief.packageUpdates(
                        briefRepository(page: page), repoId: summary.id, updates: summary.packageUpdates,
                        skipped: summary.versions?.skippedVersionSources ?? []
                    )
                }
            )
            if let versions = summary.versions, versions.error == nil {
                RepoPackagesSections(
                    versions: versions,
                    knownPackages: Set(model.packageSummaries.map(\.id)),
                    showPackage: { model.showPackage($0) },
                    brief: { workspace, showsWorkspace in
                        AgentBrief.packages(
                            briefRepository(page: page), workspace: workspace, showsWorkspace: showsWorkspace,
                            latest: model.visibleVersionReport?.latestPackages ?? [:],
                            context: model.visibleVersionReport?.updateContext(for: versions) ?? .empty,
                            skipped: versions.skippedSources
                        )
                    }
                )
            }
            if let account {
                RepoWatchSection(watch: $model[watch: summary.repo, account: account.id])
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(verbatim: summary.shortName))
        .navigationSubtitle(Text(verbatim: summary.repo))
        .toolbar {
            RepoDetailToolbar(
                model: model,
                summary: summary,
                page: page
            )
        }
        .focusedSceneValue(\.browserTarget, page.map(BrowserTarget.page))
        .focusedSceneValue(\.repoTarget, RepoTarget(id: summary.id, isOpen: true))
    }
}

private struct RepoOverviewSection: View {
    let health: RepoHealth
    let accountName: String?
    let latestTag: String?
    let checkedAt: Date?

    var body: some View {
        Section {
            LabeledContent("Status") {
                Label {
                    Text(health.label)
                } icon: {
                    Image(systemName: health.symbol).foregroundStyle(health.color)
                }
            }
            if let accountName {
                LabeledContent("Account") { Text(verbatim: accountName) }
            }
            LabeledContent("Laatste tag") {
                if let latestTag {
                    Text(verbatim: latestTag).monospacedDigit()
                } else {
                    Text("Geen")
                }
            }
            LabeledContent("Gecheckt") {
                if let checkedAt {
                    Text(checkedAt, format: .dateTime.day().month().year().hour().minute())
                } else {
                    Text("Nog niet gecheckt")
                }
            }
        }
    }
}

private struct RepoPullRequestsSection: View {
    let items: [HistoryItem]
    let openCount: Int
    let open: (HistoryItem) -> Void
    let showAll: (ItemKind) -> Void
    let brief: () -> String

    var body: some View {
        Section {
            if items.isEmpty {
                Text("Geen PR's in de geschiedenis").foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                Button {
                    open(item)
                } label: {
                    PullRequestRow(item: item)
                }
                .buttonStyle(.plain)
                .help(Text("Open in browser"))
            }
        } header: {
            HStack {
                Text("Pull requests")
                Spacer()
                if openCount > 0 {
                    Text("\(openCount) open").foregroundStyle(.secondary)
                }
                AgentBriefButton(brief: brief)
            }
        } footer: {
            HStack(spacing: 12) {
                Button("Alle PR's van deze repo") { showAll(.pullRequest) }
                Button("Alle tags van deze repo") { showAll(.tag) }
            }
            .buttonStyle(.link)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct PullRequestRow: View {
    let item: HistoryItem

    var body: some View {
        HStack(spacing: 6) {
            if let state = item.entry.prState {
                Pill(text: state.label, tint: state.color)
            }
            Text(verbatim: item.entry.title)
                .fontWeight(item.isRead ? .regular : .semibold)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let author = item.entry.author {
                Text(verbatim: author).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(item.detectedAt, format: .relative(presentation: .named))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}

private struct RepoControlSection: View {
    let versions: RepoVersions?
    let gitHubAdvisories: [String: GitHubAdvisory]
    /// De GitHub Advisory Database staat uit: de details van GitHub zijn niet opgehaald.
    let advisoryDetailsOff: Bool
    let knownPackages: Set<String>
    let showPackage: (String) -> Void
    /// nil zolang de repo niet gecheckt is: dan valt er niets te kopiëren.
    let brief: (() -> String)?

    var body: some View {
        Section {
            if let versions {
                if let error = versions.error {
                    Text(verbatim: error).foregroundStyle(.red)
                } else if versions.components.isEmpty {
                    Text("Geen talen of frameworks herkend").foregroundStyle(.secondary)
                } else {
                    ForEach(versions.components, id: \.label) { component in
                        ComponentRow(
                            component: component,
                            release: versions.release.map { release in
                                (release.tag, release.components.first { $0.label == component.label })
                            },
                            skippedSource: versions.skippedReleaseSource(of: component)
                        )
                    }
                }
                if let release = versions.release, let error = release.error {
                    Text("Tag \(release.tag) niet te checken: \(error)", comment: "Tagnaam, foutmelding").foregroundStyle(.orange)
                }
                if let vulnerabilityError = versions.vulnerabilityError {
                    Text(verbatim: vulnerabilityError).foregroundStyle(.orange)
                }
                if versions.isUnchecked(.osv) {
                    SourceOffText(text: SourceOff.notChecked(.osv), isWarning: true)
                }
                if !versions.vulnerabilities.isEmpty {
                    VulnerabilityList(
                        repo: versions, showPackage: showPackage, knownPackages: knownPackages, gitHubAdvisories: gitHubAdvisories,
                        advisoryDetailsOff: advisoryDetailsOff
                    )
                }
            } else {
                Text("Nog niet gecheckt").foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Controle")
                Spacer()
                if let tag = versions?.release?.tag {
                    Text("vs. \(tag)", comment: "Tagnaam").foregroundStyle(.secondary)
                }
                if let brief {
                    AgentBriefButton(brief: brief)
                }
            }
        }
    }
}

private struct RepoPackageUpdatesSection: View {
    let updates: [PackageSummary]
    let repoId: String
    let isChecked: Bool
    /// Registers en releasebronnen die uit stonden: dan nooit "Alles actueel".
    let skipped: [DataSourceID]
    let brief: () -> String

    var body: some View {
        Section {
            if updates.isEmpty && skipped.isEmpty {
                Text(isChecked ? "Alles actueel" : "Nog niet gecheckt").foregroundStyle(.secondary)
            }
            ForEach(skipped, id: \.self) { source in
                SourceOffText(text: SourceOff.versionsText(source))
            }
            ForEach(updates) { update in
                LabeledContent {
                    Text(verbatim: "\(update.behind.first { $0.repoId == repoId }?.version ?? "") → \(update.latest ?? "")")
                        .monospacedDigit()
                } label: {
                    Text(verbatim: update.label)
                    Text(verbatim: update.kind)
                }
            }
        } header: {
            HStack {
                Text("Packages met nieuwe versie")
                Spacer()
                if isChecked {
                    AgentBriefButton(brief: brief)
                }
            }
        }
    }
}

/// Volgen (PR's, tags, gemerged) en per soort de melding, direct opgeslagen; met dezelfde regels
/// als de lijst in Instellingen (gemerged hoort bij de PR's).
private struct RepoWatchSection: View {
    @Binding var watch: WatchSet

    var body: some View {
        Section {
            ForEach(WatchKind.allCases) { kind in
                WatchRow(title: kind.columnTitle, follow: $watch[follows: kind], notify: $watch[notifies: kind])
                    .disabled(kind == .merged && !watch.prs)
                    .help(kind.help)
            }
        } header: {
            Text("Volgen")
        } footer: {
            Text("Zonder melding staat het wel in het menu en de geschiedenis.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct WatchRow: View {
    let title: LocalizedStringKey
    @Binding var follow: Bool
    @Binding var notify: Bool

    var body: some View {
        LabeledContent {
            HStack(spacing: 16) {
                Toggle("Volgen", isOn: $follow)
                Toggle("Melding", isOn: $notify)
                    .disabled(!follow)
            }
            .toggleStyle(.checkbox)
        } label: {
            Text(title)
        }
    }
}

/// Openen, opnieuw checken, statistieken en kopiëren voor de repo-pagina.
private struct RepoDetailToolbar: ToolbarContent {
    let model: AppModel
    let summary: RepoSummary
    let page: URL?

    var body: some ToolbarContent {
        ToolbarItemGroup {
            if let page {
                Button {
                    NSWorkspace.shared.open(page)
                } label: {
                    Label("Open in browser", systemImage: "safari")
                }
                .help("Open in browser")
            }
            Button {
                Task { await model.refreshVersions(of: summary) }
            } label: {
                Label("Check", systemImage: "arrow.clockwise")
            }
            .disabled(model.versionCheck != nil || model.versionReport == nil || !model.refreshingRepos.isEmpty)
            .help(model.versionReport == nil ? Text("Check eerst alle repo's") : Text("Check deze repo opnieuw"))
            Button {
                model.showStats(repoId: summary.id)
            } label: {
                Label("Statistieken", systemImage: "chart.bar")
            }
            .help("Open de statistieken van deze repo")
            if let versions = summary.versions {
                CopyVersionsButton {
                    versions.clipboardText(
                        advisories: summary.advisories, advisoryDetailsOff: !model.config.isEnabled(.gitHubAdvisoryDatabase)
                    )
                }
            }
        }
    }
}

private struct CopyVersionsButton: View {
    let text: () -> String

    var body: some View {
        CopyButton(
            title: "Kopieer",
            help: "Kopieer de afhankelijkheden en kwetsbaarheden van deze repo naar het klembord",
            text: text
        )
    }
}
