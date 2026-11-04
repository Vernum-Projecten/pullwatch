import AppKit
import UserNotifications

/// Start de app: legt de taal vast, zet de meldingen op en start het model, behalve als host van
/// de unit-tests.
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
        // `-PullwatchSnapshotDark YES`: donkere modus voor de camera, los van de instelling van de Mac.
        if UserDefaults.standard.bool(forKey: "PullwatchSnapshotDark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        // Voor schermafbeeldingen: meteen de instellingen, het Over-venster of Erkenningen open.
        if UserDefaults.standard.bool(forKey: "PullwatchOpenSettings") { AppModel.shared.router.show(.settings) }
        if UserDefaults.standard.bool(forKey: "PullwatchOpenAbout") { AppModel.shared.router.show(.about) }
        if UserDefaults.standard.bool(forKey: "PullwatchOpenAcknowledgements") { AppModel.shared.router.show(.acknowledgements) }
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

    /// Het menu van het Dock-icoon (zolang dat er is), zoals Mail Haal nieuwe post op biedt:
    /// opnieuw laden en alle repo's checken. AppKit vraagt het bij elke klik opnieuw, dus de
    /// toestand klopt altijd.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let versions = AppModel.shared.versions
        let menu = NSMenu()
        menu.autoenablesItems = false
        let reload = NSMenuItem(title: String(localized: "Laad opnieuw"), action: #selector(reloadFromDock), keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)
        let checkAll = NSMenuItem(title: String(localized: "Alle repo's checken"), action: #selector(checkAllFromDock), keyEquivalent: "")
        checkAll.target = self
        checkAll.isEnabled = versions.versionCheck == nil && versions.refreshingRepos.isEmpty
        menu.addItem(checkAll)
        return menu
    }

    @objc private func reloadFromDock() {
        AppModel.shared.polling.refresh()
    }

    @objc private func checkAllFromDock() {
        AppModel.shared.versions.startCheck()
    }
}
