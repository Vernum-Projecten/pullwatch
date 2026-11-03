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
        // Voor schermafbeeldingen: meteen de instellingen of het Over-venster open.
        if UserDefaults.standard.bool(forKey: "PullwatchOpenSettings") { AppModel.shared.show(.settings) }
        if UserDefaults.standard.bool(forKey: "PullwatchOpenAbout") { AppModel.shared.show(.about) }
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
            CommandGroup(replacing: .appInfo) {
                Button("Over Pullwatch") { model.show(.about) }
            }
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

        Window("Over Pullwatch", id: WindowID.about.rawValue) {
            AboutView()
                .countsAsOpenWindow(WindowID.about.rawValue)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        #if DEBUG
        // Alleen voor schermafbeeldingen (`-PullwatchMenuPreview YES`): het menupaneel als gewoon
        // venster, want een MenuBarExtra laat zich niet vanzelf openen.
        Window(Text(verbatim: "Menu"), id: "menu-preview") {
            MenuView(model: model)
                .onAppear { SnapshotCamera.shoot("menu", windowId: "menu-preview") }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(UserDefaults.standard.bool(forKey: "PullwatchMenuPreview") ? .presented : .suppressed)
        #endif
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
            if model.unreadCount > 0 {
                Image(systemName: "circle.fill")
                    .imageScale(.small)
                    .accessibilityLabel(Text("Ongelezen"))
            }
        }
        .onChange(of: model.windowRequest) { _, request in
            guard let request else { return }
            // Het venster moet opengaan zolang het menupaneel nog de actieve app vertegenwoordigt;
            // sluit je het paneel eerst, dan opent het "vanuit een niet-actieve app" en komt het
            // onder andere vensters te staan. Dus: openen, activeren, paneel weg, dan naar voren.
            let panel = NSApp.keyWindow
            let windowId: String
            if request.window == .settings {
                openSettings()
                windowId = "com_apple_SwiftUI_Settings_window"
            } else {
                openWindow(id: request.window.rawValue)
                windowId = request.window.rawValue
            }
            NSApp.activate()
            // Alleen het paneel zelf sluiten, niet een gewoon venster (met titelbalk) dat toevallig de key was.
            if let panel, !panel.styleMask.contains(.titled) { panel.orderOut(nil) }
            DispatchQueue.main.async {
                NSApp.windows
                    .first { $0.identifier?.rawValue.hasPrefix(windowId) == true }?
                    .makeKeyAndOrderFront(nil)
            }
            model.windowRequest = nil
        }
    }
}
