import SwiftUI

/// Het menu Venster: Minimaliseer, Zoom en Alles op voorgrond komen van het systeem, net als de
/// lijst van open vensters. Pullwatch (⌘0) opent het hoofdvenster of haalt het naar voren; het
/// vervangt de vensters die SwiftUI per `Window`-scene zelf zou noemen (Over, Erkenningen, Welkom).
struct WindowCommands: Commands {
    let router: AppRouter

    var body: some Commands {
        CommandGroup(replacing: .singleWindowList) {
            Button {
                router.show(.main)
            } label: {
                Text(verbatim: "Pullwatch")
            }
            .keyboardShortcut("0")
        }
    }
}
