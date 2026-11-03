import AppKit
import PullwatchCore
import SwiftUI

/// Wat het zichtbare onderdeel geselecteerd heeft, voor ⌘O. Een gegeven, geen actie: de
/// opdracht doet het werk via het model.
enum BrowserTarget: Equatable {
    /// PR's of tags uit de geschiedenis (gaan bij openen op gelezen).
    case history([String])
    case page(URL)
}

/// De repo waar het zichtbare onderdeel over gaat: de selectie in een lijst, of de geopende
/// repo-pagina. Voor de repo-opdrachten in het menu Ga, die ook in de knoppenbalk staan.
struct RepoTarget: Equatable {
    /// `RepoSummary.id`.
    let id: String
    /// De pagina van deze repo staat al open.
    let isOpen: Bool
}

/// Wat de lijst van de geschiedenis toont en selecteert, voor gelezen en ongelezen.
struct ReadTarget: Equatable {
    let selected: Set<String>
    /// Wat de lijst nu toont (na zoeken en filters).
    let visible: Set<String>
    /// Zit er in de selectie iets ongelezens? Dan markeert de opdracht als gelezen, anders als ongelezen.
    let selectionHasUnread: Bool
    let visibleHasUnread: Bool
}

extension FocusedValues {
    @Entry var readTarget: ReadTarget?
    @Entry var browserTarget: BrowserTarget?
    @Entry var repoTarget: RepoTarget?
    /// De focus van het zoekveld van het zichtbare onderdeel, voor ⌘F.
    @Entry var searchFocus: FocusState<Bool>.Binding?
}

extension View {
    /// Geeft ⌘F (Zoeken in het menu Ga) het zoekveld van deze `.searchable`.
    func searchShortcut() -> some View {
        modifier(SearchShortcut())
    }
}

private struct SearchShortcut: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .searchFocused($isFocused)
            .focusedSceneValue(\.searchFocus, $isFocused)
    }
}

/// Menu "Ga" met sneltoetsen: ⌘1–5 voor de onderdelen, ⌘R verversen, ⌘[ terug, ⌘O openen, en elke
/// knop uit de knoppenbalk, zodat niets alleen daar te vinden is. ⌘F zet de focus in het zoekveld
/// van het zichtbare onderdeel.
struct ShortcutCommands: Commands {
    let model: AppModel
    @FocusedValue(\.browserTarget) private var browserTarget
    @FocusedValue(\.repoTarget) private var repoTarget
    @FocusedValue(\.readTarget) private var readTarget
    @FocusedValue(\.searchFocus) private var searchFocus

    var body: some Commands {
        CommandMenu("Ga") {
            ForEach(MainSection.allCases) { section in
                Button(section.title) { model.show(section) }
                    .keyboardShortcut(section.shortcut, modifiers: .command)
            }
            Divider()
            Button("Zoeken") { searchFocus?.wrappedValue = true }
                .keyboardShortcut("f")
                .disabled(searchFocus == nil)
            Button("Verversen") { model.refreshCurrent() }
                .keyboardShortcut("r")
            Button("Terug") { model.goBack() }
                .keyboardShortcut("[")
                .disabled(model.path.isEmpty)
            Button("Open in browser") {
                if let browserTarget { model.open(browserTarget) }
            }
            .keyboardShortcut("o")
            .disabled(browserTarget == nil || browserTarget == .history([]))
            // Zoals Mail: ⇧⌘U wisselt de selectie tussen gelezen en ongelezen.
            Button(readTarget?.selectionHasUnread == false ? "Markeer als ongelezen" : "Markeer als gelezen") {
                if let readTarget { model.setRead(readTarget.selected, readTarget.selectionHasUnread) }
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(readTarget?.selected.isEmpty ?? true)
            Button("Alles als gelezen markeren") {
                if let readTarget { model.setRead(readTarget.visible, true) }
            }
            .keyboardShortcut("k")
            .disabled(!(readTarget?.visibleHasUnread ?? false))
            Divider()
            Button("Open de pagina van de repo") {
                if let repoTarget { model.showRepo(id: repoTarget.id) }
            }
            .keyboardShortcut(.downArrow)
            .disabled(repoTarget == nil || repoTarget?.isOpen == true)
            Button("Statistieken van de repo") {
                if let repoTarget { model.showStats(repoId: repoTarget.id) }
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(repoTarget?.isOpen != true)
            Button("Kopieer de afhankelijkheden van de repo") {
                guard let summary = repoTarget.flatMap({ model.repoSummariesById[$0.id] }),
                      let text = summary.versions?.clipboardText(
                          advisories: summary.advisories, advisoryDetailsOff: !model.config.isEnabled(.gitHubAdvisoryDatabase)
                      ) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(repoTarget?.isOpen != true || repoTarget.flatMap { model.repoSummariesById[$0.id] }?.versions == nil)
            Button("Volg een repository…") { model.watchRepository() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model.accountsForExtraRepos.isEmpty)
            Divider()
            Button("Geschiedenis opnieuw ophalen") {
                Task { await model.refetchHistory() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model.refetch != nil)
            Button("Alle repo's checken") {
                Task { await model.checkVersions() }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(model.versionCheck != nil || !model.refreshingRepos.isEmpty)
            Button("Ophalen stoppen") {
                model.cancelSync()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!(model.syncStatus.work?.isCancellable ?? false))
        }
    }
}

extension MainSection {
    /// ⌘1 tot ⌘5, in de volgorde van de zijbalk.
    var shortcut: KeyEquivalent {
        let index = Self.allCases.firstIndex(of: self) ?? 0
        return KeyEquivalent(Character(String(index + 1)))
    }
}
