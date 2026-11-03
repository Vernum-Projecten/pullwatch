import Foundation
import Observation
import PullwatchCore

nonisolated private let logger = Log(category: "app")

/// Nieuwere versies van Pullwatch: de dagelijkse check, "Nu controleren" onder Instellingen en
/// het installeren, met Sparkle (`Updater`) als de build een openbare sleutel heeft.
@Observable
final class UpdatesModel {
    /// Nieuwere Pullwatch op GitHub; nil als deze versie de nieuwste is (of nog niet gekeken).
    private(set) var availableUpdate: AvailableUpdate?
    /// Uitkomst van "Nu controleren" onder Instellingen; nil als er niet handmatig gekeken is.
    private(set) var updateCheckMessage: String?
    private(set) var isCheckingForUpdates = false
    /// Updates vanzelf downloaden en bij het afsluiten installeren; Sparkle bewaart de keuze.
    private(set) var installsUpdatesAutomatically = false

    /// Sparkle, als de build een openbare sleutel heeft; anders alleen de melding met downloadknop.
    @ObservationIgnored let updater = Updater()
    @ObservationIgnored private var nextUpdateCheck: Date?
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let accounts: AccountsModel
    @ObservationIgnored private let notifications: NotificationsModel

    init(services: AppServices, accounts: AccountsModel, notifications: NotificationsModel) {
        self.services = services
        self.accounts = accounts
        self.notifications = notifications
    }

    private var config: AppConfig { accounts.config }

    /// Start Sparkle met de keuze voor testversies uit de instellingen.
    func start() {
        updater.includeTestVersions = config.includeTestVersions
        updater.start()
        installsUpdatesAutomatically = updater.installsAutomatically
    }

    /// Updates installeren in de app kan (Sparkle met een openbare sleutel in de build).
    var installsUpdatesInApp: Bool { updater.isEnabled }

    func setInstallsUpdatesAutomatically(_ on: Bool) {
        updater.installsAutomatically = on
        installsUpdatesAutomatically = updater.installsAutomatically
        if on, availableUpdate?.installsInApp == true { updater.downloadInBackground() }
    }

    /// Een andere keuze voor testversies kan een andere update geven (of geen): opnieuw kijken.
    func includeTestVersionsChanged(_ on: Bool) {
        updater.includeTestVersions = on
        nextUpdateCheck = nil
        availableUpdate = nil
    }

    /// Bij het opstarten en daarna eens per dag; mislukt het (offline), dan over een uur opnieuw.
    func startUpdateCheckIfDue() {
        guard config.checkForUpdates, !isCheckingForUpdates else { return }
        if let nextUpdateCheck, Date() < nextUpdateCheck { return }
        nextUpdateCheck = Date() + 3600
        Task { await checkForUpdates(manual: false) }
    }

    /// Kijkt op GitHub naar een nieuwere release. Automatisch: één melding per nieuwe versie.
    /// Met Sparkle uit de appcast (en met "Nu controleren" meteen Sparkle's venster); zonder
    /// sleutel uit de nieuwste release, met de DMG als download.
    func checkForUpdates(manual: Bool) async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        do {
            let update = try await findUpdate()
            availableUpdate = update
            nextUpdateCheck = Date() + UpdateChecker.interval
            if manual {
                updateCheckMessage = update.map { String(localized: "Versie \($0.version) is beschikbaar", comment: "Versienummer") }
                    ?? String(localized: "Je hebt de nieuwste versie (\(AppModel.currentVersion))", comment: "Huidig versienummer")
            }
            guard let update else { return }
            if update.installsInApp {
                if manual {
                    updater.installNow()
                } else if updater.installsAutomatically {
                    updater.downloadInBackground()
                }
            }
            let notifiedKey = "notifiedUpdateVersion"
            if !manual, UserDefaults.standard.string(forKey: notifiedKey) != update.version {
                UserDefaults.standard.set(update.version, forKey: notifiedKey)
                services.notifier.deliver([notifications.builder.appUpdate(update)])
            }
        } catch {
            logger.notice("updatecheck mislukt: \(error.localizedDescription)")
            if manual {
                let reason = (error as? ProviderError)?.userMessage ?? error.localizedDescription
                updateCheckMessage = String(localized: "Controleren mislukt: \(reason)", comment: "Reden waarom de updatecheck mislukte")
            }
        }
    }

    /// Met Sparkle de update uit de appcast (die Sparkle daarna zelf ook leest); zonder
    /// sleutel de nieuwste release.
    private func findUpdate() async throws -> AvailableUpdate? {
        let http = URLSessionHTTPClient()
        guard updater.isEnabled else {
            return try await UpdateChecker.check(current: AppModel.currentVersion, owner: updater.owner, http: http)
        }
        let feed = try await UpdateFeed.url(owner: updater.owner, includeTestVersions: config.includeTestVersions, http: http)
        updater.feedURL = feed
        let item = try await UpdateFeed.newest(
            feed: feed,
            currentBuild: Updater.currentBuild,
            includeTestVersions: config.includeTestVersions,
            system: ProcessInfo.processInfo.operatingSystemVersion,
            http: http
        )
        return item.map { AvailableUpdate($0, owner: updater.owner) }
    }

    /// De update installeren: Sparkle's venster met de release notes en Installeren.
    func installUpdate() {
        updater.installNow()
    }
}
