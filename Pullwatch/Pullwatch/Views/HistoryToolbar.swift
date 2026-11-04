import PullwatchCore
import SwiftUI

/// Een token in het zoekveld: een auteur of een repo.
struct HistoryTokenLabel: View {
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
struct HistoryContextMenu: View {
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
struct HistoryToolbar: ToolbarContent {
    @Environment(AppModel.self) private var app
    @Environment(PollingModel.self) private var polling
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
                polling.startRefetch()
            } label: {
                Label("Opnieuw ophalen", systemImage: "arrow.clockwise")
            }
            .disabled(polling.refetch != nil)
            .help("Haalt de PR's van alle accounts opnieuw op binnen de bewaartermijn, één account tegelijk (zonder meldingen)")
        }
        ToolbarSpacer(.fixed)
        ToolbarItem {
            Button {
                if let selectedRepo { app.showRepo(accountId: selectedRepo.accountId, repo: selectedRepo.repo) }
            } label: {
                Label("Repo", systemImage: "folder")
            }
            .disabled(selectedRepo == nil)
            .help(selectedRepo.map { Text("Open de pagina van \($0.repo)") } ?? Text("Selecteer een PR of tag van één repo"))
        }
    }
}
