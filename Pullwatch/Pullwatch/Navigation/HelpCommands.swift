import AppKit
import SwiftUI

/// Het menu Help: eerst de documentatie op de website, dan wat er nieuw is, Privacy en bronnen
/// (Instellingen, Bronnen: elke verbinding die Pullwatch maakt), een probleem melden en de
/// erkenningen. Het zoekveld van het menu komt van het systeem.
struct HelpCommands: Commands {
    let router: AppRouter

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Pullwatch-help") { NSWorkspace.shared.open(HelpLinks.documentation) }
            Button("Toetscombinaties") { NSWorkspace.shared.open(HelpLinks.keyboardShortcuts) }
            Divider()
            Button("Nieuw in Pullwatch") { NSWorkspace.shared.open(HelpLinks.releaseNotes(version: AppModel.currentVersion)) }
            Button("Privacy en bronnen") { router.showSettings(.sources) }
            Button("Meld een probleem…") { NSWorkspace.shared.open(HelpLinks.newIssue) }
            Divider()
            Button("Erkenningen") { router.show(.acknowledgements) }
        }
    }
}
