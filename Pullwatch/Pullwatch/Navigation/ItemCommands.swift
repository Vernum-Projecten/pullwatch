import SwiftUI

/// Het menu Onderdeel: de gekozen pull request, tag of release. Gelezen of ongelezen, alles
/// gelezen, en de link of de verwijzing (`FerroHEALTH/FerroFED#1570`) kopiëren.
struct ItemCommands: Commands {
    let model: AppModel
    @FocusedValue(\.readTarget) private var readTarget
    @FocusedValue(\.browserTarget) private var browserTarget

    var body: some Commands {
        CommandMenu("Onderdeel") {
            // Zoals Mail: ⇧⌘U wisselt de selectie tussen gelezen en ongelezen.
            Button(readTarget?.selectionHasUnread == false ? "Markeer als ongelezen" : "Markeer als gelezen") {
                if let readTarget { model.historyModel.setRead(readTarget.selected, readTarget.selectionHasUnread) }
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(readTarget?.selected.isEmpty ?? true)
            Button("Alles als gelezen markeren") {
                if let readTarget { model.historyModel.setRead(readTarget.visible, true) }
            }
            .keyboardShortcut("k")
            .disabled(!(readTarget?.visibleHasUnread ?? false))
            Divider()
            Button("Kopieer link") {
                guard let browserTarget else { return }
                let links = model.historyModel.links(of: browserTarget)
                if !links.isEmpty { Pasteboard.copy(links.map(\.absoluteString).joined(separator: "\n")) }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(browserTarget == nil || browserTarget == .history([]))
            // De verwijzing zoals de dienst hem schrijft (`FerroHEALTH/FerroFED#1570`, `group/app!42`),
            // om in een commit, issue of chat te plakken.
            Button("Kopieer verwijzing") {
                guard let browserTarget else { return }
                let references = model.historyModel.references(of: browserTarget)
                if !references.isEmpty { Pasteboard.copy(references.joined(separator: "\n")) }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift, .option])
            .disabled(browserTarget.map { model.historyModel.references(of: $0).isEmpty } ?? true)
        }
    }
}
