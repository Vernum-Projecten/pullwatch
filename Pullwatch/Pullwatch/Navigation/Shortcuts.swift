import SwiftUI

// De gegevens waar de menu's van de menubalk (`AppCommands`) op werken: wat het zichtbare
// onderdeel van het hoofdvenster geselecteerd heeft, als focused value.

/// Wat het zichtbare onderdeel geselecteerd heeft, voor ⌘O en ⇧⌘L. Een gegeven, geen actie: de
/// opdracht doet het werk via het model.
enum BrowserTarget: Equatable {
    /// PR's of tags uit de geschiedenis (gaan bij openen op gelezen).
    case history([String])
    case page(URL)
}

/// De repo waar het zichtbare onderdeel over gaat: de selectie in een lijst, of de geopende
/// repo-pagina. Voor het menu Repository, waarvan de opdrachten ook in de knoppenbalk staan.
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

extension MainSection {
    /// ⌘1 tot ⌘6, in de volgorde van de zijbalk.
    var shortcut: KeyEquivalent {
        let index = Self.allCases.firstIndex(of: self) ?? 0
        return KeyEquivalent(Character(String(index + 1)))
    }
}
