import AppKit
import ServiceManagement
import SwiftUI

/// "Starten bij inloggen" via `SMAppService`. Leest de echte stand bij verschijnen en bij
/// terugkomen in de app (iemand kan het onder Systeeminstellingen → Inlogonderdelen veranderen),
/// en toont een knop naar die instellingen als macOS eerst goedkeuring vraagt.
struct LaunchAtLoginToggle: View {
    @State private var status = SMAppService.Status.notRegistered
    @State private var error: String?

    var body: some View {
        LabeledContent {
            if status == .requiresApproval {
                Button("Open Inlogonderdelen") { SMAppService.openSystemSettingsLoginItems() }
            } else {
                Toggle("Starten bij inloggen", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        } label: {
            Text("Starten bij inloggen")
            if status == .requiresApproval {
                Text("Keur Pullwatch goed onder Systeeminstellingen → Algemeen → Inlogonderdelen.")
            } else if let error {
                Text(verbatim: error).foregroundStyle(.red)
            }
        }
        .accessibilityIdentifier("launchAtLogin")
        .task {
            status = SMAppService.mainApp.status
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                status = SMAppService.mainApp.status
            }
        }
    }

    /// Aan- of uitzetten, en daarna de echte stand van macOS laten zien.
    private var isOn: Binding<Bool> {
        Binding(
            get: { status == .enabled },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    error = nil
                } catch {
                    self.error = error.localizedDescription
                }
                status = SMAppService.mainApp.status
            }
        )
    }
}
