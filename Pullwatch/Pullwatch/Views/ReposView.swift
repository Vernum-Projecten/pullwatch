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
    @Environment(AppModel.self) private var app
    @Environment(AccountsModel.self) private var accounts
    @Environment(PollingModel.self) private var polling
    @Environment(VersionsModel.self) private var versions
    @Environment(OverviewModel.self) private var overview
    @Environment(AppRouter.self) private var router
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
        let all = overview.repoSummaries.filter { group == nil || $0.group == group }
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
        guard let selection, let summary = overview.repoSummariesById[selection] else { return nil }
        return accounts.config.accounts.first { $0.id == summary.accountId }?.repoWebURL(summary.repo)
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
            if let id = ids.first, let summary = overview.repoSummariesById[id] {
                Button("Open de pagina van deze repo") { router.showRepo(id: id) }
                if let url = accounts.config.accounts.first(where: { $0.id == summary.accountId })?.repoWebURL(summary.repo) {
                    Button("Open in browser") { NSWorkspace.shared.open(url) }
                }
                Button("Check deze repo opnieuw") {
                    versions.startRefresh(of: summary)
                }
                .disabled(versions.versionCheck != nil || versions.versionReport == nil)
            }
        } primaryAction: { ids in
            if let id = ids.first { router.showRepo(id: id) }
        }
        .overlay {
            if rows.isEmpty {
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty
                    && (polling.isFillingHistory || versions.versionCheck != nil) {
                    // De voortgang staat in de balk onderin; hier alleen wat er gebeurt.
                    ContentUnavailableView(
                        "Repo's ophalen…",
                        systemImage: "folder",
                        description: polling.fillingAccountName.map {
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
        .navigationSubtitle(CheckedSubtitle.text(versions.versionReport?.checkedAt))
        .toolbar {
            ToolbarItem {
                Button {
                    app.watchRepository()
                } label: {
                    Label("Volg een repository…", systemImage: "plus")
                }
                .disabled(accounts.accountsForExtraRepos.isEmpty)
                .help("Een losse repository volgen, ook een openbare van een andere organisatie")
            }
            CheckAllToolbarItem()
        }
        .onChange(of: Query(text: searchText, sortOrder: sortOrder, summaries: overview.repoSummaries), initial: true) {
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
    @Environment(VersionsModel.self) private var versions

    var body: some ToolbarContent {
        ToolbarItem {
            Button {
                versions.startCheck()
            } label: {
                Label("Alles checken", systemImage: "checkmark.shield")
            }
            .disabled(versions.versionCheck != nil || !versions.refreshingRepos.isEmpty)
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
