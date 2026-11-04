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
            // Een eigen sleutel: in een menu schrijft het Engels elk woord met een hoofdletter.
            Button(String(localized: "menu.file.openInBrowser", defaultValue: "Open in browser", comment: "Menu Archief: de selectie in de browser openen")) {
                if let browserTarget { model.historyModel.open(browserTarget) }
            }
            .keyboardShortcut("o")
            .disabled(browserTarget == nil || browserTarget == .history([]))
        }
    }
}
