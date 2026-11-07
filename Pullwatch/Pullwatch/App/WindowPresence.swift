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

    @ObservationIgnored private var badgeTask: Task<Void, Never>?

    func opened(_ window: String) { openWindows.insert(window) }
    func closed(_ window: String) { openWindows.remove(window) }

    private func updateActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = openWindows.isEmpty ? .accessory : .regular
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .regular {
            NSApp.activate()
            redrawDockBadge()
        }
    }

    /// Het Dock maakt een nieuwe tegel als de app `.regular` wordt, en tekent er de badge niet op
    /// die AppKit al had (gezet bij het starten of zonder venster, `HistoryModel.updateDockBadge`).
    /// Meteen na de wissel opnieuw zetten is te vroeg; een tiende seconde later staat hij erop
    /// (nagegaan met een losse app in het Dock).
    private func redrawDockBadge() {
        badgeTask?.cancel()
        badgeTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
            guard NSApp.activationPolicy() == .regular else { return }
            let tile = NSApp.dockTile
            let label = tile.badgeLabel
            tile.badgeLabel = nil
            tile.badgeLabel = label
        }
    }
}

extension View {
    /// Dit venster telt mee voor het Dock-icoon zolang het open is.
    func countsAsOpenWindow(_ window: String) -> some View {
        onAppear { WindowPresence.shared.opened(window) }
            .onDisappear { WindowPresence.shared.closed(window) }
    }
}
