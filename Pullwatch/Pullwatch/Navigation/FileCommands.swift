import SwiftUI

/// Het menu Archief: een nieuw account, een repository volgen en de selectie in de browser
/// openen. Sluit venster komt van het systeem.
struct FileCommands: Commands {
    let model: AppModel
    @FocusedValue(\.browserTarget) private var browserTarget

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nieuw account…") { model.router.addAccount() }
                .keyboardShortcut("n")
            Button("Volg een repository…") { model.watchRepository() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model.accounts.accountsForExtraRepos.isEmpty)
            Divider()
            Button("Open in browser") {
                if let browserTarget { model.historyModel.open(browserTarget) }
            }
            .keyboardShortcut("o")
            .disabled(browserTarget == nil || browserTarget == .history([]))
        }
    }
}
