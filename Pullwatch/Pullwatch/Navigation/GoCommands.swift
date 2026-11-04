import SwiftUI

/// Het menu Ga: terug, de onderdelen van de zijbalk (⌘1 tot ⌘5) en de pagina van de gekozen
/// repository. Vooruit ontbreekt: `AppRouter` houdt alleen een pad bij, geen weg vooruit.
struct GoCommands: Commands {
    let model: AppModel
    @FocusedValue(\.repoTarget) private var repoTarget

    var body: some Commands {
        CommandMenu("Ga") {
            Button("Terug") { model.router.goBack() }
                .keyboardShortcut("[")
                .disabled(model.router.path.isEmpty)
            Divider()
            ForEach(MainSection.allCases) { section in
                Button(section.title) { model.router.show(section) }
                    .keyboardShortcut(section.shortcut, modifiers: .command)
            }
            Divider()
            Button("Repositorypagina") {
                if let repoTarget { model.router.showRepo(id: repoTarget.id) }
            }
            .keyboardShortcut(.downArrow)
            .disabled(repoTarget == nil || repoTarget?.isOpen == true)
        }
    }
}
