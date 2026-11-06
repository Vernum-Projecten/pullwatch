import PullwatchCore
import SwiftUI

// Het tabblad Overzicht van de repo-pagina: status, pull requests, activiteit en volgen.

struct RepoOverviewSection: View {
    let health: RepoHealth
    let accountName: String?
    let latestTag: String?
    let checkedAt: Date?
    /// Wat de repo zelf publiceert (het onderdeel Packages); leeg als niets of de bron uit staat.
    var published: [PublishedPackage] = []
    /// Opent Packages, gefilterd op deze repo.
    var showPublished: () -> Void = {}

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
            if !published.isEmpty {
                RepoPublishedRow(packages: published, show: showPublished)
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

/// Eén regel: wat de repo publiceert, met de nieuwste versies, als link naar het onderdeel Packages.
struct RepoPublishedRow: View {
    let packages: [PublishedPackage]
    let show: () -> Void

    var body: some View {
        LabeledContent("Publiceert") {
            Button(action: show) {
                Text(verbatim: packages.map { package in
                    package.latestVersion.map { "\(package.name) \($0)" } ?? package.name
                }.formatted(.list(type: .and)))
                .multilineTextAlignment(.trailing)
            }
            .buttonStyle(.link)
            .help(Text("Toon deze packages in Packages"))
        }
    }
}

struct RepoPullRequestsSection: View {
    let items: [HistoryItem]
    /// De dienst van het account, voor het teken van het PR-nummer; nil zonder account.
    let providerKind: ProviderKind?
    let openCount: Int
    /// De bron CI-checks staat aan.
    let showsChecks: Bool
    let open: (HistoryItem) -> Void
    let showAll: (ItemKind) -> Void
    /// Kopieert de lijst als opdracht voor een AI-agent (`AgentBrief.pullRequests`).
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
                    PullRequestRow(item: item, kind: providerKind, showsChecks: showsChecks)
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
            VStack(alignment: .trailing, spacing: 6) {
                if items.contains(where: { $0.entry.checks == .needsPermission }) {
                    ChecksPermissionNote(isEnabled: showsChecks)
                }
                HStack(spacing: 12) {
                    Button("Alle PR's van deze repo") { showAll(.pullRequest) }
                    Button("Alle tags van deze repo") { showAll(.tag) }
                }
                .buttonStyle(.link)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// De checks van PR's in deze repo mag Pullwatch niet lezen: dan staat er geen cel, en hier
/// waarom, met wat er nodig is.
private struct ChecksPermissionNote: View {
    /// De bron CI-checks staat aan; anders vraagt Pullwatch geen checks, dus ook geen toestemming.
    let isEnabled: Bool

    var body: some View {
        if isEnabled {
            HStack(spacing: 4) {
                Text("Checks")
                Text("Toestemming nodig").foregroundStyle(.secondary)
            }
            .font(.caption)
            .help(Text("Pullwatch mag de checks van deze PR's niet lezen. Bij GitHub keurt de eigenaar de rechten Checks en Commit statuses (lezen) van de Pullwatch-app goed; bij Azure DevOps en GitLab mag het token de builds of pipelines lezen."))
            .accessibilityElement(children: .combine)
        }
    }
}

/// Eén PR in een lijst: de status als Octicon in zijn kleur, zoals de PR-lijst van het
/// hoofdvenster, daarachter het nummer (`#1570`) ingetogen zoals de telling van de checks, en de
/// titel; de repo staat al boven de pagina. De status staat in woorden in de tooltip en voor
/// VoiceOver ("Gemergde pull request 1570: titel"). Leest zelf geen model uit de environment (zie
/// `ChecksBadge`).
struct PullRequestRow: View {
    let item: HistoryItem
    /// De dienst van het account, voor het teken van het nummer; nil: geen nummer.
    let kind: ProviderKind?
    /// De bron CI-checks staat aan.
    let showsChecks: Bool

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                item.entry.glyph.image
                    .foregroundStyle(item.entry.glyphColor)
                    .frame(width: 16)
                    .help(Text(item.entry.glyphLabel))
                if case .pullRequest(let pr) = item.entry, let kind {
                    Text(verbatim: pr.numberText(kind))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize()
                        .help(pr.reference(kind))
                }
                Text(verbatim: item.entry.title)
                    .fontWeight(item.isRead ? .regular : .semibold)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenTitle)
            ChecksBadge(checks: item.entry.checks, isEnabled: showsChecks)
            Spacer(minLength: 8)
            if let author = item.entry.author {
                Text(verbatim: author).foregroundStyle(.secondary).lineLimit(1)
            }
            RelativeDateText(date: item.detectedAt)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }

    /// Status, nummer en titel als één zin; bij een tag alleen de titel.
    private var spokenTitle: Text {
        guard case .pullRequest(let pr) = item.entry, let status = item.entry.prStatus else {
            return Text(verbatim: item.entry.title)
        }
        return Text(status.spokenSentence(number: pr.number, title: pr.title))
    }
}

/// Volgen (PR's, tags, gemerged) en per soort de melding, direct opgeslagen; met dezelfde regels
/// als de lijst in Instellingen (gemerged hoort bij de PR's).
struct RepoWatchSection: View {
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

struct WatchRow: View {
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
