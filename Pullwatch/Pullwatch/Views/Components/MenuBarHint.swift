import AppKit
import PullwatchCore
import SwiftUI
import UserNotifications

/// Een nagetekende menubalk met het Pullwatch-icoon gemarkeerd, zodat je weet waar je moet kijken.
/// Tekststijlen in plaats van vaste maten, zodat hij meegroeit met grotere tekst; voor VoiceOver
/// één beschrijving in plaats van losse symbolen.
struct MenuBarHint: View {
    /// Zo hoog als de tekst ernaast, en groeit mee met grotere tekst.
    @ScaledMetric(relativeTo: .body) private var iconHeight = 17.0

    var body: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            Image(.menuBarIcon)
                .resizable()
                .scaledToFit()
                .frame(height: iconHeight)
                .padding(6)
                .background { Circle().fill(.tint.opacity(0.18)) }
                .overlay { Circle().strokeBorder(.tint, lineWidth: 2) }
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Image(systemName: "switch.2")
            Text(Date.now, format: .dateTime.weekday(.abbreviated).hour().minute())
                .monospacedDigit()
        }
        .font(.body)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: 440, minHeight: iconHeight + 24)
        .background(.bar, in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("De menubalk, met het Pullwatch-icoon rechtsboven naast de klok"))
    }
}
