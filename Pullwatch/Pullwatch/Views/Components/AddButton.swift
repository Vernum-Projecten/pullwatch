import AppKit
import PullwatchCore
import SwiftUI
import UserNotifications

/// Toevoegen in een voetbalk: grijs met de reden ernaast zolang het account niet af is, daarna
/// de blauwe standaardknop (ook met Return).
struct AddButton: View {
    let action: AccountSaveAction

    var body: some View {
        HStack(spacing: 10) {
            // Op twee regels als het niet past, nooit afgekapt; VoiceOver hoort de reden ook bij
            // de knop zelf.
            if let error = action.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let reason = action.blockedReason {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            Button("Toevoegen") { action.save() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!action.canSave)
                .accessibilityHint(action.blockedReason.map { Text($0) } ?? Text(verbatim: ""))
                .accessibilityIdentifier("account.save")
        }
    }
}
