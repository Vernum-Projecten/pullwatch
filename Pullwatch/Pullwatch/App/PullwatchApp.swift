import AppKit
import PullwatchCore
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // De taal van deze run vastleggen voordat Instellingen iets kan wijzigen.
        _ = AppLanguage.atLaunch
        // Als host van de unit-tests niet pollen, melden of naar updates kijken: dat zou met
        // de echte accounts en tokens van de ontwikkelaar gebeuren.
        if AppModel.isTestHost { return }
        UNUserNotificationCenter.current().delegate = Notifier.shared
        AppModel.shared.start()
        #if DEBUG
        // Voor schermafbeeldingen: meteen de instellingen of het Over-venster open.
        if UserDefaults.standard.bool(forKey: "PullwatchOpenSettings") { AppModel.shared.router.show(.settings) }
        if UserDefaults.standard.bool(forKey: "PullwatchOpenAbout") { AppModel.shared.router.show(.about) }
        #endif
    }

    /// De app opnieuw openen terwijl hij al draait (Finder, Spotlight, Launchpad, `open`)
    /// opent het hoofdvenster, of het welkomstvenster zolang er geen account is; anders gebeurt
    /// er zichtbaar niets en lijkt Pullwatch kapot.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let model = AppModel.shared
        model.router.show(model.accounts.needsOnboarding ? .onboarding : .main)
        return false
    }
}

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
    /// Geeft een venster de modellen van de app mee in de environment. Elke view leest daar
    /// alleen het model dat hij nodig heeft (`@Environment(PollingModel.self)`), zodat een
    /// wijziging in een ander model hem niet opnieuw laat tekenen.
    func appModels(_ app: AppModel) -> some View {
        environment(app)
            .environment(app.accounts)
            .environment(app.historyModel)
            .environment(app.notifications)
            .environment(app.versions)
            .environment(app.overview)
            .environment(app.polling)
            .environment(app.updates)
            .environment(app.router)
    }

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
            MenuView()
                .appModels(model)
        } label: {
            MenuBarLabel()
                .appModels(model)
        }
        .menuBarExtraStyle(.window)

        Window("Pullwatch", id: WindowID.main.rawValue) {
            MainView()
                .appModels(model)
                .countsAsOpenWindow(WindowID.main.rawValue)
        }
        .commands {
            ShortcutCommands(model: model)
            CommandGroup(replacing: .appInfo) {
                Button("Over Pullwatch") { model.router.show(.about) }
            }
        }
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)

        Window("Welkom bij Pullwatch", id: WindowID.onboarding.rawValue) {
            OnboardingView()
                .appModels(model)
                .countsAsOpenWindow(WindowID.onboarding.rawValue)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        // Eerste start: meteen het welkomstvenster, anders lijkt de app niet te starten.
        .defaultLaunchBehavior(model.opensOnboardingAtLaunch ? .presented : .suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .appModels(model)
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
            MenuView()
                .appModels(model)
                .onAppear { SnapshotCamera.shoot("menu", windowId: "menu-preview") }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(UserDefaults.standard.bool(forKey: "PullwatchMenuPreview") ? .presented : .suppressed)

        // Alleen voor schermafbeeldingen (`-PullwatchNotificationPreview YES`, met
        // `-PullwatchSkipNotificationRequest YES`): elke soort melding zoals de builder hem maakt,
        // getekend in een venster in plaats van verstuurd.
        Window(Text(verbatim: "Notifications"), id: "notification-preview") {
            NotificationPreviewGallery()
                .onAppear { SnapshotCamera.shoot("notifications", windowId: "notification-preview") }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(UserDefaults.standard.bool(forKey: "PullwatchNotificationPreview") ? .presented : .suppressed)
        #endif
    }
}

/// Icoon in de menubalk. Bestaat zolang de app draait, en opent daarom de vensters waar het
/// model om vraagt (`windowRequest`): alleen een view heeft `openWindow`.
private struct MenuBarLabel: View {
    @Environment(AccountsModel.self) private var accounts
    @Environment(HistoryModel.self) private var historyModel
    @Environment(PollingModel.self) private var polling
    @Environment(AppRouter.self) private var router
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 2) {
            if polling.hasPollError {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityLabel(Text("Pullwatch, een account geeft een fout"))
            } else {
                // Het pull-request-teken van het app-icoon, als template.
                Image(.menuBarIcon)
                    .accessibilityLabel(Text(verbatim: "Pullwatch"))
            }
            if historyModel.unreadCount > 0 && accounts.config.notifications.menuBarDot {
                Image(systemName: "circle.fill")
                    .imageScale(.small)
                    .accessibilityLabel(Text("Ongelezen"))
            }
        }
        .onChange(of: router.windowRequest) { _, request in
            guard let request else { return }
            // Het venster moet opengaan zolang het menupaneel nog de actieve app vertegenwoordigt;
            // sluit je het paneel eerst, dan opent het "vanuit een niet-actieve app" en komt het
            // onder andere vensters te staan. Dus: openen, activeren, paneel weg, dan naar voren.
            let panel = MenuPanel.current()
            let windowId: String
            if request.window == .settings {
                openSettings()
                windowId = "com_apple_SwiftUI_Settings_window"
            } else {
                openWindow(id: request.window.rawValue)
                windowId = request.window.rawValue
            }
            NSApp.activate()
            panel?.orderOut(nil)
            // Een beurt later: dan heeft SwiftUI het venster gemaakt.
            Task {
                await Task.yield()
                MenuPanel.window(id: windowId)?.makeKeyAndOrderFront(nil)
            }
            router.windowRequest = nil
        }
    }
}

#if DEBUG
/// Elke soort melding onder elkaar, ook met de stille uren en de samenvatting boven de grens.
private struct NotificationPreviewGallery: View {
    private let samples = NotificationSamples(builder: NotificationContentBuilder())

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(NotificationKind.allCases) { kind in
                if let content = samples.content(for: kind) {
                    NotificationPreview(content: content)
                }
            }
            NotificationPreview(content: samples.summary)
        }
        .padding(16)
        .frame(width: 420)
    }
}
#endif
