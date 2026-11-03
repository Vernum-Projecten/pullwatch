import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Als host van de unit-tests niet pollen, melden of naar updates kijken: dat zou met
        // de echte accounts en tokens van de ontwikkelaar gebeuren.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        _ = AppLanguage.atLaunch
        UNUserNotificationCenter.current().delegate = Notifier.shared
        AppModel.shared.start()
        DockIcon.shared.start()
    }

    /// De app opnieuw openen terwijl hij al draait (Finder, Spotlight, Launchpad, `open`)
    /// opent het hoofdvenster; anders gebeurt er zichtbaar niets en lijkt Pullwatch kapot.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let openMainWindow = AppModel.shared.openMainWindow {
            openMainWindow()
        } else {
            NSApp.activate()
        }
        return false
    }
}

/// Toont Pullwatch in het Dock zolang er een eigen venster (instellingen, hoofdvenster)
/// open is; zonder venster draait de app weer alleen in de menubalk.
@MainActor
final class DockIcon {
    static let shared = DockIcon()
    static let windowIds = ["main"]

    func start() {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didMiniaturizeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { DockIcon.shared.update() }
            }
        }
        // Bij willClose is het venster nog zichtbaar; daarom pas daarna kijken.
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { DockIcon.shared.update() } }
        }
    }

    private func update() {
        let hasWindow = NSApp.windows.contains { window in
            (window.isVisible || window.isMiniaturized)
                && Self.windowIds.contains { window.identifier?.rawValue.hasPrefix($0) == true }
        }
        let policy: NSApplication.ActivationPolicy = hasWindow ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if hasWindow { NSApp.activate() }
    }
}

@main
struct PullwatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Pullwatch", id: "main") {
            MainView(model: model)
        }
        .commands {
            ShortcutCommands(model: model)
            CommandGroup(replacing: .appSettings) {
                Button("Instellingen…") {
                    model.mainSection = .settings
                    model.openMainWindow?()
                }
                .keyboardShortcut(",")
            }
        }
        .windowResizability(.contentMinSize)
    }
}

/// Icoon in de menubalk. Bestaat zolang de app draait en geeft het model daarom de `openWindow`-actie.
private struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: model.menuBarSymbol)
            if model.history.unreadCount > 0 {
                Text("•")
            }
        }
        .onAppear {
            model.openMainWindow = {
                openWindow(id: "main")
                NSApp.activate()
            }
        }
    }
}
