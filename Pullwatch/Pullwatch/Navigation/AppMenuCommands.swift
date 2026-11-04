import SwiftUI

/// Het app-menu: Over Pullwatch en Controleer op updates…; Instellingen, Diensten, Verberg en
/// Stop komen van het systeem.
struct AppMenuCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Over Pullwatch") { model.router.show(.about) }
        }
        CommandGroup(after: .appInfo) {
            Divider()
            // Uit zolang Sparkle een check doet, en in een build zonder Sparkle-sleutel.
            Button("Controleer op updates…") { model.updates.startCheckFromMenu() }
                .disabled(!model.updates.canCheckFromMenu)
        }
    }
}
