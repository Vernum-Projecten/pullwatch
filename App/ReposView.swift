import AppKit
import PullwatchCore
import SwiftUI

extension RepoHealth {
    var color: Color {
        switch self {
        case .problem: .red
        case .behind: .orange
        case .ok: .green
        case .unknown: .secondary.opacity(0.4)
        }
    }
}

/// Gevolgde repo's, slechtste eerst; een klik opent de pagina van die repo.
struct ReposView: View {
    let model: AppModel
    /// Alleen dit project (uit de zijbalk); nil voor alles.
    var group: HistoryGroup.ID? = nil
    var groupName: String? = nil

    @State private var searchText = ""

    private var summaries: [RepoSummary] {
        let all = model.repoSummaries.filter { group == nil || $0.group == group }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { summary in
            summary.repo.localizedCaseInsensitiveContains(query)
                || (summary.versions?.components.contains { $0.label.localizedCaseInsensitiveContains(query) } ?? false)
                || (summary.versions?.vulnerabilities.contains {
                    $0.package.localizedCaseInsensitiveContains(query) || ($0.cve ?? $0.id).localizedCaseInsensitiveContains(query)
                } ?? false)
        }
    }

    var body: some View {
        if let id = model.selectedRepoId, let summary = model.repoSummaries.first(where: { $0.id == id }) {
            RepoDetailView(model: model, summary: summary, backTitle: groupName)
        } else {
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(
                    groupName.map { String(localized: "Zoek in \($0)…", comment: "Projectnaam") }
                        ?? String(localized: "Zoek op repo, taal of CVE…"),
                    text: $searchText
                )
                .textFieldStyle(.roundedBorder)
                CheckAllButton(model: model)
            }
            if let report = model.versionReport {
                Text("Gecheckt \(report.checkedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            let shown = summaries
            if shown.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "Geen repo's",
                        systemImage: "folder",
                        description: Text("Volg repo's in Instellingen en check ze om hier te zien hoe ze ervoor staan.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(shown) { summary in
                            RepoRow(summary: summary, showsProject: group == nil) { model.selectedRepoId = summary.id }
                            Divider()
                        }
                    }
                }
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
    }
}

/// "Alles checken" of de voortgang van de lopende check.
private struct CheckAllButton: View {
    let model: AppModel

    var body: some View {
        if let progress = model.versionCheck {
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                .frame(width: 100)
            Text("Checken… \(progress.done)/\(progress.total) repo's")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else {
            Button("Alles checken") {
                Task { await model.checkVersions() }
            }
            .help("Leest per gevolgde repo de taal- en frameworkversies en vergelijkt ze met endoflife.date; packages gaan langs OSV.dev voor bekende CVE's en langs hun register voor de nieuwste versie")
        }
    }
}

private struct RepoRow: View {
    let summary: RepoSummary
    let showsProject: Bool
    let action: () -> Void

    private var name: String {
        showsProject ? summary.repo : String(summary.repo.split(separator: "/", maxSplits: 1).last ?? Substring(summary.repo))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(summary.health.color).frame(width: 8, height: 8)
                Text(name).fontWeight(.semibold)
                ForEach(RepoLabel.labels(for: summary), id: \.text) { label in
                    Text(label.text)
                        .font(.caption)
                        .foregroundStyle(label.color)
                        .padding(.horizontal, 7)
                        .overlay(Capsule().strokeBorder(label.color.opacity(0.5)))
                }
                Spacer()
                Text(summary.openPullRequests == 1 ? String(localized: "1 PR") : String(localized: "\(summary.openPullRequests) PR's"))
                    .foregroundStyle(summary.openPullRequests == 0 ? .tertiary : .secondary)
                if let tag = summary.latestTag {
                    Label(tag, systemImage: "tag").foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Korte labels in de lijst: CVE's, slechtste runtime, packages met een nieuwe versie.
private struct RepoLabel {
    let text: String
    let color: Color

    static func labels(for summary: RepoSummary) -> [RepoLabel] {
        guard let versions = summary.versions else { return [RepoLabel(text: String(localized: "nog niet gecheckt"), color: .secondary)] }
        if versions.error != nil { return [RepoLabel(text: String(localized: "check mislukt"), color: .secondary)] }
        var labels: [RepoLabel] = []
        let cves = versions.vulnerabilities.count
        if cves > 0 {
            labels.append(RepoLabel(text: cves == 1 ? String(localized: "1 CVE") : String(localized: "\(cves) CVE's"), color: .red))
        }
        if let worst = versions.components.filter({ $0.status == .eol || $0.status == .behind }).max(by: { $0.status < $1.status }) {
            labels.append(RepoLabel(text: "\(worst.label) \(worst.version) \(worst.status.label.lowercased())", color: worst.status.color))
        }
        let updates = summary.packageUpdates.count
        if updates > 0 {
            labels.append(RepoLabel(
                text: updates == 1 ? String(localized: "1 nieuwe versie") : String(localized: "\(updates) nieuwe versies"),
                color: .orange
            ))
        }
        if labels.isEmpty { labels.append(RepoLabel(text: String(localized: "actueel"), color: .green)) }
        return labels
    }
}

/// Alles over één repo: PR's, controle (runtimes en CVE's) en packages met een nieuwe versie.
private struct RepoDetailView: View {
    let model: AppModel
    let summary: RepoSummary
    let backTitle: String?

    @State private var copied = false

    private var account: Account? { model.config.accounts.first { $0.id == summary.accountId } }

    private var pullRequests: [HistoryItem] {
        let items = model.history.items.filter {
            $0.entry.kind == .pullRequest && $0.entry.accountId == summary.accountId
                && $0.entry.repo.caseInsensitiveCompare(summary.repo) == .orderedSame
        }
        // Open eerst, daarna de rest op volgorde van binnenkomst.
        return Array((items.filter { $0.entry.prState == .open } + items.filter { $0.entry.prState != .open }).prefix(10))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                DetailSection(title: "Pull requests", trailing: summary.openPullRequests == 0 ? nil : String(localized: "\(summary.openPullRequests) open")) {
                    if pullRequests.isEmpty {
                        Text("Geen PR's in de geschiedenis").foregroundStyle(.secondary)
                    } else {
                        ForEach(pullRequests) { item in
                            Button {
                                model.open(item)
                            } label: {
                                HStack(spacing: 6) {
                                    if let state = item.entry.prState { StatePill(state: state) }
                                    Text(item.entry.title).fontWeight(item.isRead ? .regular : .bold).lineLimit(1)
                                    Text(verbatim: "· \(item.entry.author ?? String(localized: "onbekend")) ·").foregroundStyle(.secondary)
                                    Text(item.detectedAt, format: .relative(presentation: .named)).foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                DetailSection(title: "Activiteit", trailing: String(localized: "PR's per maand")) {
                    ActivityChart(
                        stats: ActivityStats.compute(history: model.history, period: .month, filter: ActivityFilter(repoId: summary.id)),
                        period: .month
                    )
                    .frame(height: 120)
                }
                DetailSection(title: "Controle", trailing: summary.versions?.release.map { String(localized: "vs. \($0.tag)", comment: "Tagnaam") }) {
                    control
                }
                DetailSection(title: "Packages met nieuwe versie", trailing: summary.packageUpdates.isEmpty ? nil : "\(summary.packageUpdates.count)") {
                    if summary.packageUpdates.isEmpty {
                        Text(summary.versions == nil ? String(localized: "Nog niet gecheckt") : String(localized: "Alles actueel"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(summary.packageUpdates) { update in
                            HStack(spacing: 6) {
                                Text(update.label)
                                Text(verbatim: "\(update.behind.first { $0.repoId == summary.id }?.version ?? "") → \(update.latest ?? "")")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Text(update.kind).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.selectedRepoId = nil
            } label: {
                Label(backTitle ?? String(localized: "Repo's"), systemImage: "chevron.left")
            }
            .buttonStyle(.link)
            HStack(spacing: 8) {
                Circle().fill(summary.health.color).frame(width: 10, height: 10)
                Text(summary.repo).font(.title2.bold())
            }
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if let url = account?.repoWebURL(summary.repo) {
                    Button("Open in browser") { NSWorkspace.shared.open(url) }
                }
                if model.refreshingRepos.contains(summary.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await model.refreshVersions(of: summary) }
                    } label: {
                        Label("Check", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.versionCheck != nil || model.versionReport == nil)
                    .help(model.versionReport == nil ? String(localized: "Check eerst alle repo's") : String(localized: "Check deze repo opnieuw"))
                }
                Button {
                    model.showStats(repoId: summary.id)
                } label: {
                    Label("Statistieken", systemImage: "chart.bar")
                }
                .help("Open de statistieken van deze repo")
                if let versions = summary.versions {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(versions.clipboardText, forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .help("Kopieer de versies en kwetsbaarheden van deze repo naar het klembord")
                }
                Spacer()
                if let account {
                    WatchControls(model: model, account: account, repo: summary.repo)
                }
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let account { parts.append("\(account.displayName) · \(account.kind == .azureDevOps ? "Azure DevOps" : "GitHub")") }
        if let tag = summary.latestTag { parts.append(String(localized: "laatste tag \(tag)", comment: "Tagnaam")) }
        if let report = model.versionReport, summary.versions != nil {
            parts.append(String(localized: "gecheckt \(report.checkedAt.formatted(date: .abbreviated, time: .shortened))"))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var control: some View {
        if let versions = summary.versions {
            if let error = versions.error {
                Text(error).foregroundStyle(.red)
            } else if versions.components.isEmpty {
                Text("Geen talen of frameworks herkend").foregroundStyle(.secondary)
            } else {
                ForEach(versions.components, id: \.label) { component in
                    ComponentRow(
                        component: component,
                        release: versions.release.map { release in
                            (release.tag, release.components.first { $0.label == component.label })
                        }
                    )
                }
            }
            if let release = versions.release, let error = release.error {
                Text("Tag \(release.tag) niet te checken: \(error)", comment: "Tagnaam, foutmelding").foregroundStyle(.orange)
            }
            if let vulnerabilityError = versions.vulnerabilityError {
                Text(vulnerabilityError).foregroundStyle(.orange)
            }
            if !versions.vulnerabilities.isEmpty {
                VulnerabilityList(repo: versions, isExpanded: true)
            }
        } else {
            Text("Nog niet gecheckt").foregroundStyle(.secondary)
        }
    }
}

private struct DetailSection<Content: View>: View {
    let title: LocalizedStringKey
    let trailing: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.caption.bold()).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                if let trailing {
                    Text(verbatim: trailing).font(.caption).foregroundStyle(.secondary)
                }
            }
            content.font(.callout)
        }
    }
}

/// Volgen (PR's, Tags, Completed) en per soort de melding, direct opgeslagen.
private struct WatchControls: View {
    let model: AppModel
    let account: Account
    let repo: String

    private func binding(_ path: WritableKeyPath<WatchSet, Bool>) -> Binding<Bool> {
        Binding(
            get: { account.watch(for: repo)[keyPath: path] },
            set: { value in
                var set = account.watch(for: repo)
                set[keyPath: path] = value
                model.setWatch(set, repo: repo, accountId: account.id)
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            watchToggle("PR's", \.prs, notify: \.notifyPRs)
            watchToggle("Tags", \.tags, notify: \.notifyTags)
            watchToggle("Completed", \.completed, notify: \.notifyCompleted)
        }
    }

    private func watchToggle(_ title: LocalizedStringKey, _ follow: WritableKeyPath<WatchSet, Bool>, notify: WritableKeyPath<WatchSet, Bool>) -> some View {
        HStack(spacing: 2) {
            Toggle(title, isOn: binding(follow))
                .toggleStyle(.button)
            Button {
                binding(notify).wrappedValue.toggle()
            } label: {
                Image(systemName: binding(notify).wrappedValue ? "bell.fill" : "bell.slash")
                    .foregroundStyle(binding(notify).wrappedValue ? Color.primary : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!binding(follow).wrappedValue)
            .help(binding(notify).wrappedValue ? String(localized: "Melding aan; klik om alleen te volgen zonder melding") : String(localized: "Geen melding; staat wel in menu en geschiedenis"))
        }
    }
}
