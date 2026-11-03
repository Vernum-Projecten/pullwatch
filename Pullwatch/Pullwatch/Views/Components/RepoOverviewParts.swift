import PullwatchCore
import SwiftUI

// Het tabblad Overzicht van de repo-pagina: status, pull requests, activiteit en volgen.

struct RepoOverviewSection: View {
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

struct RepoPullRequestsSection: View {
    let items: [HistoryItem]
    let openCount: Int
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
            VStack(alignment: .trailing, spacing: 6) {
                if items.contains(where: { $0.entry.checks == .needsPermission }) {
                    ChecksPermissionNote()
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
    @Environment(AccountsModel.self) private var accounts

    var body: some View {
        // Met de bron CI-checks uit vraagt Pullwatch geen checks, dus ook geen toestemming.
        if accounts.config.isEnabled(.ciChecks) {
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

struct PullRequestRow: View {
    let item: HistoryItem

    var body: some View {
        HStack(spacing: 6) {
            if let state = item.entry.prState {
                Pill(text: state.label, tint: state.color)
            }
            Text(verbatim: item.entry.title)
                .fontWeight(item.isRead ? .regular : .semibold)
                .lineLimit(1)
            ChecksBadge(checks: item.entry.checks)
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
