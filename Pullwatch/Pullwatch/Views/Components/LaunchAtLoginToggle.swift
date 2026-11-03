import ServiceManagement
import SwiftUI

/// "Starten bij inloggen" via `SMAppService`; toont de fout als macOS het weigert.
struct LaunchAtLoginToggle: View {
    @State private var isOn = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        Toggle("Starten bij inloggen", isOn: $isOn)
            .accessibilityIdentifier("launchAtLogin")
            .onChange(of: isOn) { _, enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    error = nil
                } catch {
                    self.error = error.localizedDescription
                    isOn = SMAppService.mainApp.status == .enabled
                }
            }
        if let error {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }
}
