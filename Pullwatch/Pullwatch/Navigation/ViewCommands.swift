import SwiftUI

/// Het menu Weergave: zijbalk en knoppenbalk tonen of verbergen (van het systeem, met een titel
/// die de toestand volgt), opnieuw laden, en schermvullend (ook van het systeem).
struct ViewCommands: Commands {
    let model: AppModel

    var body: some Commands {
        SidebarCommands()
        ToolbarCommands()
        CommandGroup(after: .sidebar) {
            Divider()
            Button("Laad opnieuw") { model.refreshCurrent() }
                .keyboardShortcut("r")
        }
    }
}
