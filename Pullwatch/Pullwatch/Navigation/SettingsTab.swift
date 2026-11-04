import Foundation

/// De tabbladen van Instellingen. `AppRouter.settingsTab` is het gekozen tabblad; het venster bindt
/// zijn tabbladen eraan, zodat een knop, menu of melding Instellingen op een tabblad kan openen
/// (`AppRouter.showSettings(_:)`).
enum SettingsTab: String, CaseIterable {
    case accounts, notifications, general, sources, agents

    /// Het tabblad bij een klik op een melding naar Instellingen: de vraag van een agent opent
    /// Agents, een account met een verlopen token Accounts.
    static func forNotification(_ payload: NotificationPayload) -> SettingsTab {
        payload.agentName != nil ? .agents : .accounts
    }
}
