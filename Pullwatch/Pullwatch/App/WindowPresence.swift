import AppKit
import SwiftUI

/// Toont Pullwatch in het Dock zolang er een eigen venster open is (hoofdvenster, welkomstvenster,
/// instellingen); zonder venster draait de app alleen in de menubalk. Elk venster meldt zich met
/// `.countsAsOpenWindow(_:)`; een geminimaliseerd venster blijft meetellen.
@Observable
final class WindowPresence {
    static let shared = WindowPresence()

    private(set) var openWindows: Set<String> = [] {
        didSet { updateActivationPolicy() }
    }

    func opened(_ window: String) { openWindows.insert(window) }
    func closed(_ window: String) { openWindows.remove(window) }

    private func updateActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = openWindows.isEmpty ? .accessory : .regular
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .regular { NSApp.activate() }
    }
}

extension View {
    /// Dit venster telt mee voor het Dock-icoon zolang het open is.
    func countsAsOpenWindow(_ window: String) -> some View {
        onAppear { WindowPresence.shared.opened(window) }
            .onDisappear { WindowPresence.shared.closed(window) }
    }
}
