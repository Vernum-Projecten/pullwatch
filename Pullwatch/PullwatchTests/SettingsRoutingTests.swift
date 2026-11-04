import Foundation
import Testing

@testable import Pullwatch

/// Instellingen op een tabblad openen via `AppRouter`: `showSettings(_:)` kiest het tabblad en
/// opent het venster, `show(.settings)` laat het laatst gekozen tabblad staan, en een klik op een
/// melding naar Instellingen kiest het tabblad dat bij de melding hoort.
@MainActor @Suite struct SettingsRoutingTests {
    let router = AppRouter()

    @Test func `Settings open on Accounts the first time`() {
        #expect(router.settingsTab == .accounts)
    }

    @Test(arguments: SettingsTab.allCases)
    func `Opening Settings on a tab selects it and opens the window`(_ tab: SettingsTab) {
        router.showSettings(tab)

        #expect(router.settingsTab == tab)
        #expect(router.windowRequest?.window == .settings)
    }

    @Test func `Opening Settings without a tab keeps the last tab`() {
        router.settingsTab = .sources
        router.show(.settings)

        #expect(router.settingsTab == .sources)
        #expect(router.windowRequest?.window == .settings)
    }

    @Test func `New Account opens Settings on Accounts`() {
        router.settingsTab = .agents
        router.addAccount()

        #expect(router.settingsTab == .accounts)
        #expect(router.addsAccount)
        #expect(router.windowRequest?.window == .settings)
    }

    @Test func `The agent approval notification opens Agents`() {
        let content = NotificationContentBuilder(quiet: false).agentApproval(clientName: "codex-mcp-client", displayName: "Codex")

        #expect(content.payload.section == "settings")
        #expect(SettingsTab.forNotification(content.payload) == .agents)
    }

    @Test func `A notification about an account opens Accounts`() {
        #expect(SettingsTab.forNotification(NotificationPayload(section: "settings")) == .accounts)
    }
}
