import AppKit
import PullwatchCore
import SwiftUI

struct HistoryView: View {
    let model: AppModel
    let kind: ItemKind
    /// Alleen dit project (uit de zijbalk); nil voor alles.
    var group: HistoryGroup.ID? = nil
    var groupName: String? = nil

    @State private var searchText = ""
    // Zonder selectie-binding vuurt de primaryAction (dubbelklik) van contextMenu niet.
    @State private var selection = Set<HistoryItem.ID>()

    private var items: [HistoryItem] {
        model.history.search(searchText, kind: kind, group: group,
                             author: model.historyFilter?.author, repo: model.historyFilter?.repo)
    }

    /// Account en repo van de selectie, als die over één repo gaat.
    private func repo(of ids: Set<HistoryItem.ID>) -> (accountId: UUID, name: String)? {
        let entries = model.history.items.filter { ids.contains($0.id) }.map(\.entry)
        guard let first = entries.first,
              entries.allSatisfy({ $0.accountId == first.accountId && $0.repo == first.repo }) else { return nil }
        return (first.accountId, first.repo)
    }

    private var selectedRepo: (accountId: UUID, name: String)? { repo(of: selection) }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField(
                    groupName.map { String(localized: "Zoek in \($0)…", comment: "Projectnaam") } ?? String(localized: "Zoek op titel, auteur, repo…"),
                    text: $searchText
                )
                    .textFieldStyle(.roundedBorder)
                    .searchFocus(model)
                if let progress = model.refetch {
                    ProgressView(value: Double(progress.done), total: Double(progress.total))
                        .frame(width: 100)
                    Text("Ophalen… \(progress.done)/\(progress.total) accounts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Button("Opnieuw ophalen") {
                        Task { await model.refetchHistory() }
                    }
                    .help("Haalt de PR's van alle accounts opnieuw op binnen de bewaartermijn, één account tegelijk (zonder meldingen)")
                }
                Button {
                    if let selectedRepo { model.showRepo(accountId: selectedRepo.accountId, repo: selectedRepo.name) }
                } label: {
                    Label("Repo", systemImage: "folder")
                }
                .disabled(selectedRepo == nil)
                .help(selectedRepo.map { String(localized: "Open de pagina van \($0.name)") } ?? String(localized: "Selecteer een PR of tag van één repo"))
            }

            if let filter = model.historyFilter {
                HStack(spacing: 6) {
                    if let author = filter.author {
                        FilterChip(title: author, systemImage: "person") { model.historyFilter?.author = nil }
                    }
                    if let repo = filter.repo {
                        FilterChip(title: repo.repo, systemImage: "folder") { model.historyFilter?.repo = nil }
                    }
                    Spacer()
                }
            }

            Table(items, selection: $selection) {
                TableColumn("Type") { item in
                    KindPill(kind: item.entry.kind)
                }
                .width(50)
                TableColumn("Status") { item in
                    if let state = item.entry.prState {
                        StatePill(state: state)
                    }
                }
                .width(80)
                TableColumn("Titel") { item in
                    Text(item.entry.title)
                        .fontWeight(item.isRead ? .regular : .bold)
                        .lineLimit(1)
                }
                TableColumn("Repo") { item in
                    Text(item.entry.repo).lineLimit(1)
                }
                TableColumn("Auteur") { item in
                    Text(item.entry.author ?? "—").lineLimit(1)
                }
                .width(min: 80, ideal: 120)
                TableColumn("Wanneer") { item in
                    Text(item.detectedAt, format: .relative(presentation: .named))
                        .help(item.detectedAt.formatted(date: .complete, time: .standard))
                }
                .width(min: 90, ideal: 130)
            }
            .contextMenu(forSelectionType: HistoryItem.ID.self) { ids in
                if let repo = repo(of: ids) {
                    Button("Open \(repo.name)") { model.showRepo(accountId: repo.accountId, repo: repo.name) }
                }
            } primaryAction: { ids in
                for id in ids {
                    if let item = model.history.items.first(where: { $0.id == id }) {
                        model.open(item)
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 720, minHeight: 420)
        .onChange(of: model.openInBrowserRequest) {
            for item in items where selection.contains(item.id) {
                model.open(item)
            }
        }
    }
}
