import SwiftUI

extension View {
    /// Geeft ⌘F (Zoek… in het menu Wijzig) het zoekveld van deze `.searchable`.
    func searchShortcut() -> some View {
        modifier(SearchShortcut())
    }
}

private struct SearchShortcut: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .searchFocused($isFocused)
            .focusedSceneValue(\.searchFocus, $isFocused)
    }
}
