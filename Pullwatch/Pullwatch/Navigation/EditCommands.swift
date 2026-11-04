import SwiftUI

/// Het menu Wijzig: de standaardonderdelen van het systeem, met Zoek… (⌘F) dat de focus in het
/// zoekveld van het zichtbare onderdeel zet.
struct EditCommands: Commands {
    @FocusedValue(\.searchFocus) private var searchFocus

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Zoek…") { searchFocus?.wrappedValue = true }
                .keyboardShortcut("f")
                .disabled(searchFocus == nil)
        }
    }
}
