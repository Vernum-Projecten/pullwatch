import AppKit
import PullwatchCore
import SwiftUI
import UserNotifications

/// Meldingen zoals macOS-apps het doen: de vraag van macOS komt vanzelf zodra deze stap
/// verschijnt, de rij wacht op het antwoord, en bij "Niet toestaan" (of eerder uitgezet) opent
/// een knop de meldingsinstellingen van Pullwatch. Terug uit Systeeminstellingen ziet de rij
/// de nieuwe stand vanzelf.
struct NotificationPermissionRow: View {
    @Environment(NotificationsModel.self) private var notifications
    @State private var status: UNAuthorizationStatus?
    @State private var asking = false
    /// Telt de klikken op Vragen; de vraag loopt in een `.task` van deze rij, die hem bezit.
    @State private var askRequests = 0

    /// UI-tests slaan de vraag over: die zou een echt systeemvenster openen.
    private var requestsByItself: Bool { !UserDefaults.standard.bool(forKey: "PullwatchSkipNotificationRequest") }

    var body: some View {
        LabeledContent {
            trailing
        } label: {
            Text("Meldingen")
            Text(detail)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.notifications")
        .task {
            status = await notifications.notificationStatus()
            if status == .notDetermined && requestsByItself { await ask() }
            // Terug uit Systeeminstellingen: de nieuwe stand meteen laten zien.
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                status = await notifications.notificationStatus()
            }
        }
        .task(id: askRequests) {
            if askRequests > 0 { await ask() }
        }
    }

    private func ask() async {
        asking = true
        await notifications.requestNotifications()
        status = await notifications.notificationStatus()
        asking = false
    }

    private var detail: LocalizedStringKey {
        switch status {
        case .authorized, .provisional, .ephemeral:
            "Pullwatch meldt een nieuwe PR of tag zodra die er is."
        case .denied:
            "Meldingen staan uit. Zet ze aan in Systeeminstellingen om nieuwe PR's en tags te zien zodra ze er zijn."
        default:
            asking ? "Wachten op je antwoord in de melding van macOS…" : "Pullwatch meldt een nieuwe PR of tag zodra die er is. macOS vraagt één keer om toestemming."
        }
    }

    @ViewBuilder private var trailing: some View {
        switch status {
        case .authorized, .provisional, .ephemeral:
            Label("Aan", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            Button("Open Systeeminstellingen") { Notifier.openSystemSettings() }
                .accessibilityIdentifier("onboarding.openNotificationSettings")
        default:
            if asking {
                ProgressView().controlSize(.small)
            } else {
                Button("Vragen") { askRequests += 1 }
                .accessibilityIdentifier("onboarding.allowNotifications")
            }
        }
    }
}
