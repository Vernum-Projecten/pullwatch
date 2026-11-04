import Foundation
import Observation
import PullwatchCore
import UserNotifications

/// Of Pullwatch mag melden, de builder voor de inhoud van een melding met de accounts en stille
/// uren van nu, en de laatste "Repo dempen" die het menu nog ongedaan kan maken. Afleveren doet
/// de `Notifier`; wat een klik op een melding doet regelt `AppModel`.
@Observable
final class NotificationsModel {
    private(set) var notificationsAllowed = true
    /// De laatste "Repo dempen" van een melding, zodat het menu hem ongedaan kan maken.
    private(set) var recentMute: RepositoryMute?

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let accounts: AccountsModel

    init(services: AppServices, accounts: AccountsModel) {
        self.services = services
        self.accounts = accounts
    }

    /// De builder met de accounts van nu en, binnen de stille uren, zonder geluid en banner.
    var builder: NotificationContentBuilder {
        let config = accounts.config
        return NotificationContentBuilder(accounts: config.accounts, quiet: config.notifications.quietHours.contains(Date()))
    }

    // MARK: - Toestemming

    /// Vraagt macOS om meldingen; toont de vraag alleen de eerste keer.
    func requestNotifications() async {
        notificationsAllowed = await services.notifier.requestAuthorization()
    }

    func notificationStatus() async -> UNAuthorizationStatus {
        let status = await services.notifier.authorizationStatus()
        notificationsAllowed = status == .authorized || status == .provisional
        return status
    }

    /// Kijkt opnieuw of macOS meldingen toestaat (iemand kan het in Systeeminstellingen wijzigen).
    func refreshAuthorization() async {
        notificationsAllowed = await services.notifier.isAuthorized()
    }

    // MARK: - Dempen

    func remember(_ mute: RepositoryMute) {
        recentMute = mute
    }

    func dismissMute() {
        recentMute = nil
    }
}
