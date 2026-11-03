import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Als host van de unit-tests niet pollen, melden of naar updates kijken: dat zou met
        // de echte accounts en tokens van de ontwikkelaar gebeuren.
        if AppModel.isTestHost { return }
        UNUserNotificationCenter.current().delegate = Notifier.shared
        AppModel.shared.start()
        #if DEBUG
        // Voor schermafbeeldingen: meteen de instellingen open.
        if UserDefaults.standard.bool(forKey: "PullwatchOpenSettings") { AppModel.shared.show(.settings) }
        #endif
    }

    /// De app opnieuw openen terwijl hij al draait (Finder, Spotlight, Launchpad, `open`)
    /// opent het hoofdvenster, of het welkomstvenster zolang er geen account is; anders gebeurt
    /// er zichtbaar niets en lijkt Pullwatch kapot.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let model = AppModel.shared
        model.show(model.needsOnboarding ? .onboarding : .main)
        return false
    }
}

/// Toont Pullwatch in het Dock zolang er een eigen venster open is (hoofdvenster, welkomstvenster,
/// instellingen); zonder venster draait de app alleen in de menubalk. Elk venster meldt zich met
/// `.countsAsOpenWindow(_:)`; een geminimaliseerd venster blijft meetellen.
@MainActor
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

        Window("Pullwatch", id: WindowID.main.rawValue) {
            MainView(model: model)
                .countsAsOpenWindow(WindowID.main.rawValue)
        }
        .commands {
            ShortcutCommands(model: model)
        }
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)

        Window("Welkom bij Pullwatch", id: WindowID.onboarding.rawValue) {
            OnboardingView(model: model)
                .countsAsOpenWindow(WindowID.onboarding.rawValue)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        // Eerste start: meteen het welkomstvenster, anders lijkt de app niet te starten.
        .defaultLaunchBehavior(model.opensOnboardingAtLaunch ? .presented : .suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(model: model)
                .countsAsOpenWindow("settings")
        }
    }
}

/// Icoon in de menubalk. Bestaat zolang de app draait, en opent daarom de vensters waar het
/// model om vraagt (`windowRequest`): alleen een view heeft `openWindow`.
private struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 2) {
            if model.hasPollError {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityLabel(Text("Pullwatch, een account geeft een fout"))
            } else {
                // Het pull-request-teken van het app-icoon, als template.
                Image(.menuBarIcon)
                    .accessibilityLabel(Text(verbatim: "Pullwatch"))
            }
            if model.history.unreadCount > 0 {
                Image(systemName: "circle.fill")
                    .imageScale(.small)
                    .accessibilityLabel(Text("Ongelezen"))
            }
        }
        .onChange(of: model.windowRequest) { _, request in
            guard let request else { return }
            if request.window == .settings {
                openSettings()
            } else {
                openWindow(id: request.window.rawValue)
            }
            NSApp.activate()
            model.windowRequest = nil
        }
    }
}
