import PullwatchCore
import SwiftUI

/// Alle PR's of tags uit de geschiedenis in een tabel: zoeken, sorteren, filters als tokens.
struct HistoryView: View {
    @Bindable var model: AppModel
    let kind: ItemKind
    /// Alleen dit project (uit de zijbalk); nil voor alles.
    var group: HistoryGroup.ID? = nil
    var groupName: String? = nil

    @State private var searchText = ""
    @State private var selection = Set<HistoryItem.ID>()
    @State private var sortOrder = [KeyPathComparator(\HistoryItem.detectedAt, order: .reverse)]
    /// Gefilterd en gesorteerd; opnieuw berekend als zoektekst, tokens, volgorde of geschiedenis verandert.
    @State private var rows: [HistoryItem] = []
    /// Auteurs die bij de zoektekst passen, als voorstel voor een token.
    @State private var suggestedAuthors: [String] = []

    private struct Query: Equatable {
        let text: String
        let tokens: [HistoryToken]
        let sortOrder: [KeyPathComparator<HistoryItem>]
    }

    private var query: Query { Query(text: searchText, tokens: model.historyTokens, sortOrder: sortOrder) }

    private func recompute() {
        let tokens = model.historyTokens
        let authors = Set(tokens.compactMap { if case .author(let name) = $0 { name } else { nil } })
        let repos = tokens.compactMap { if case .repo(let repo) = $0 { repo } else { nil } }
        let found = model.history.search(searchText, kind: kind, group: group).filter { item in
            (authors.isEmpty || item.entry.author.map(authors.contains) == true)
                && (repos.isEmpty || repos.contains {
                    $0.accountId == item.entry.accountId && $0.repo.caseInsensitiveCompare(item.entry.repo) == .orderedSame
                })
        }
        rows = found.sorted(using: sortOrder)

        let text = searchText.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            suggestedAuthors = []
        } else {
            let names = Set(model.history.items.compactMap(\.entry.author)
                .filter { $0.localizedCaseInsensitiveContains(text) && !authors.contains($0) })
            suggestedAuthors = Array(names.sorted().prefix(5))
        }
    }

    /// Account en repo van deze items, als ze allemaal over één repo gaan.
    private func repo(of ids: Set<HistoryItem.ID>) -> HistoryRepo? {
        let entries = rows.filter { ids.contains($0.id) }.map(\.entry)
        guard let first = entries.first,
              entries.allSatisfy({ $0.accountId == first.accountId && $0.repo == first.repo }) else { return nil }
        return HistoryRepo(accountId: first.accountId, repo: first.repo)
    }

    /// De dienst van het account van dit item, voor de foto's bij de auteur.
    private func kind(of item: HistoryItem) -> ProviderKind {
        model.config.accounts.first { $0.id == item.entry.accountId }?.kind ?? .azureDevOps
    }

    private func open(_ ids: Set<HistoryItem.ID>) {
        model.open(.history(Array(ids)))
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Soort") { item in
                Pill(text: item.entry.kind.pillText, tint: item.entry.kind.color)
            }
            .width(44)
            TableColumn("Status") { item in
                if let state = item.entry.prState {
                    Pill(text: state.label, tint: state.color)
                }
            }
            .width(76)
            TableColumn("Titel", value: \.entry.title) { item in
                // Zoals Mail en het menupaneel: een blauwe stip voor ongelezen, op een vaste plek.
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.isRead ? AnyShapeStyle(.clear) : AnyShapeStyle(.tint))
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(verbatim: item.entry.title)
                        .fontWeight(item.isRead ? .regular : .semibold)
                        .lineLimit(1)
                        .help(item.entry.title)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(item.isRead ? Text(verbatim: "") : Text("Ongelezen"))
            }
            .width(min: 180, ideal: 300)
            TableColumn("Repo", value: \.entry.repo) { item in
                Text(verbatim: item.entry.repo).lineLimit(1)
            }
            .width(min: 100, ideal: 180)
            TableColumn("Auteur", value: \.authorSortKey) { item in
                if let author = item.entry.author {
                    ContributorsLabel(author: author, coAuthors: item.entry.coAuthors, kind: kind(of: item))
                } else {
                    Text("onbekend").foregroundStyle(.secondary)
                }
            }
            .width(min: 100, ideal: 190)
            TableColumn("Wanneer", value: \.detectedAt) { item in
                Text(item.detectedAt, format: .relative(presentation: .named))
                    .help(item.detectedAt.formatted(date: .complete, time: .standard))
            }
            .width(min: 110, ideal: 150)
        }
        .contextMenu(forSelectionType: HistoryItem.ID.self) { ids in
            HistoryContextMenu(
                count: ids.count,
                hasUnread: rows.contains { ids.contains($0.id) && !$0.isRead },
                visibleHasUnread: rows.contains { !$0.isRead },
                setRead: { model.setRead(ids, $0) },
                markAllRead: { model.setRead(Set(rows.map(\.id)), true) },
                repo: repo(of: ids),
                author: rows.first { ids.contains($0.id) }?.entry.author,
                open: { open(ids) },
                showRepo: { model.showRepo(accountId: $0.accountId, repo: $0.repo) },
                filterAuthor: { name in
                    if !model.historyTokens.contains(.author(name)) { model.historyTokens.append(.author(name)) }
                }
            )
        } primaryAction: { ids in
            open(ids)
        }
        .overlay {
            if rows.isEmpty {
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty && model.historyTokens.isEmpty
                    && model.isFillingHistory {
                    // De voortgang staat in de balk onderin; hier alleen wat er gebeurt.
                    ContentUnavailableView(
                        kind == .pullRequest ? "PR's ophalen…" : "Tags ophalen…",
                        systemImage: kind.symbol,
                        description: fillingDescription
                    )
                } else if searchText.trimmingCharacters(in: .whitespaces).isEmpty && model.historyTokens.isEmpty {
                    ContentUnavailableView(
                        kind == .pullRequest ? "Nog geen PR's" : "Nog geen tags",
                        systemImage: kind.symbol,
                        description: Text(kind == .pullRequest
                                          ? "Nieuwe pull requests in de repo's die je volgt komen hier te staan."
                                          : "Nieuwe tags in de repo's die je volgt komen hier te staan.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .searchable(
            text: $searchText,
            tokens: $model.historyTokens,
            prompt: groupName.map { Text("Zoek in \($0)…", comment: "Projectnaam") } ?? Text("Zoek op titel, auteur, repo…")
        ) { token in
            HistoryTokenLabel(token: token)
        }
        .searchShortcut()
        .searchSuggestions {
            ForEach(suggestedAuthors, id: \.self) { name in
                Label(name, systemImage: "person")
                    .searchCompletion(HistoryToken.author(name))
            }
        }
        .navigationTitle(groupName.map { Text(verbatim: $0) } ?? Text(kind == .pullRequest ? "PR's" : "Tags"))
        .navigationSubtitle(subtitle)
        .toolbar {
            HistoryToolbar(
                model: model,
                selectedRepo: repo(of: selection),
                markAllRead: { model.setRead(Set(rows.map(\.id)), true) },
                hasUnread: rows.contains { !$0.isRead }
            )
        }
        .onChange(of: query, initial: true) { recompute() }
        .onChange(of: model.history) { recompute() }
        .focusedSceneValue(\.browserTarget, .history(rows.filter { selection.contains($0.id) }.map(\.id)))
        .focusedSceneValue(\.readTarget, ReadTarget(
            selected: Set(rows.filter { selection.contains($0.id) }.map(\.id)),
            visible: Set(rows.map(\.id)),
            selectionHasUnread: rows.contains { selection.contains($0.id) && !$0.isRead },
            visibleHasUnread: rows.contains { !$0.isRead }
        ))
        .focusedSceneValue(\.repoTarget, repo(of: selection).map {
            RepoTarget(id: model.repoId(accountId: $0.accountId, repo: $0.repo), isOpen: false)
        })
    }

    /// Onder "PR's ophalen…": van welk account, als dat bekend is.
    private var fillingDescription: Text {
        guard let account = model.fillingAccountName else {
            return Text(kind == .pullRequest
                        ? "Pullwatch haalt de PR's op van de repo's die je volgt."
                        : "Pullwatch haalt de tags op van de repo's die je volgt.")
        }
        return kind == .pullRequest
            ? Text("Pullwatch haalt de PR's op van \(account).", comment: "Accountnaam, bv. @octocat op GitHub")
            : Text("Pullwatch haalt de tags op van \(account).", comment: "Accountnaam, bv. @octocat op GitHub")
    }

    private var subtitle: Text {
        let unread = rows.count(where: { !$0.isRead })
        return unread == 0 ? Text("Niets ongelezen") : Text("\(unread) ongelezen")
    }
}

// Waarden voor sorteren en tonen, geen UI-state: buiten de main actor bruikbaar (KeyPathComparator).
nonisolated extension HistoryItem {
    /// Sorteersleutel voor de kolom Auteur; zonder auteur achteraan.
    var authorSortKey: String { entry.author ?? "\u{10FFFF}" }
}

/// Een token in het zoekveld: een auteur of een repo.
private struct HistoryTokenLabel: View {
    let token: HistoryToken

    var body: some View {
        switch token {
        case .author(let name): Label(name, systemImage: "person")
        case .repo(let repo): Label(repo.repo, systemImage: "folder")
        }
    }
}

/// Rechtermuisklik op de lijst: op rijen openen, gelezen of ongelezen (zoals Mail: wat de
/// selectie nog niet is), de repo en de auteur; op een lege plek alles als gelezen.
private struct HistoryContextMenu: View {
    let count: Int
    let hasUnread: Bool
    let visibleHasUnread: Bool
    let setRead: (Bool) -> Void
    let markAllRead: () -> Void
    let repo: HistoryRepo?
    let author: String?
    let open: () -> Void
    let showRepo: (HistoryRepo) -> Void
    let filterAuthor: (String) -> Void

    var body: some View {
        if count > 0 {
            Button("Open in browser", action: open)
            Button(hasUnread ? "Markeer als gelezen" : "Markeer als ongelezen") { setRead(hasUnread) }
            Divider()
        }
        if let repo {
            Button("Open \(repo.repo)") { showRepo(repo) }
        }
        if count == 1, let author {
            Button {
                filterAuthor(author)
            } label: {
                Text("Alleen van \(author)", comment: "Auteur")
            }
        }
        if count == 0 {
            Button("Alles als gelezen markeren", action: markAllRead)
                .disabled(!visibleHasUnread)
        }
    }
}

/// Opnieuw ophalen en de repo van de selectie openen. De knop blijft staan (uitgeschakeld)
/// terwijl het loopt; de voortgang staat in de balk onderin het venster.
private struct HistoryToolbar: ToolbarContent {
    let model: AppModel
    let selectedRepo: HistoryRepo?
    let markAllRead: () -> Void
    let hasUnread: Bool

    var body: some ToolbarContent {
        ToolbarItem {
            Button(action: markAllRead) {
                Label("Alles als gelezen markeren", systemImage: "envelope.open")
            }
            .disabled(!hasUnread)
            .help("Markeert alles in deze lijst als gelezen (⌘K)")
        }
        ToolbarItem {
            Button {
                Task { await model.refetchHistory() }
            } label: {
                Label("Opnieuw ophalen", systemImage: "arrow.clockwise")
            }
            .disabled(model.refetch != nil)
            .help("Haalt de PR's van alle accounts opnieuw op binnen de bewaartermijn, één account tegelijk (zonder meldingen)")
        }
        ToolbarSpacer(.fixed)
        ToolbarItem {
            Button {
                if let selectedRepo { model.showRepo(accountId: selectedRepo.accountId, repo: selectedRepo.repo) }
            } label: {
                Label("Repo", systemImage: "folder")
            }
            .disabled(selectedRepo == nil)
            .help(selectedRepo.map { Text("Open de pagina van \($0.repo)") } ?? Text("Selecteer een PR of tag van één repo"))
        }
    }
}
