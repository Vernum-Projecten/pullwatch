import PullwatchCore
import SwiftUI

/// De plek van een PR in de merge queue of merge train (`#2`), achter het status-icoon. Ingetogen
/// zoals het PR-nummer (`RepoReferenceLabel`): secundair en met cijfers van gelijke breedte, zodat
/// hij er staat zonder op te vallen. VoiceOver hoort de plek al in het label van het icoon
/// (`HistoryEntry.glyphLabel`). Leest zelf geen model uit de environment (zie `ChecksBadge`).
struct QueuePositionText: View {
    let position: Int

    var body: some View {
        Text(verbatim: "#\(position)")
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .accessibilityHidden(true)
    }
}
