import AppKit
import PullwatchCore
import SwiftUI

/// Icoon in de menubalk. Bestaat zolang de app draait, en opent daarom de vensters waar het
/// model om vraagt (`windowRequest`): alleen een view heeft `openWindow`.
struct MenuBarLabel: View {
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
