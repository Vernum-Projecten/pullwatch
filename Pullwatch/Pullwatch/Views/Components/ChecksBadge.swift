import PullwatchCore
import SwiftUI

/// De checks van een PR zoals in de PR-lijst van GitHub: de Octicon van de stand in zijn kleur
/// (een vinkje, een kruis of een stip) en de telling "4/8", zonder woorden. De woorden staan in
/// de tooltip en in VoiceOver. Zonder checks, of zonder toestemming om ze te lezen, niets.
struct ChecksBadge: View {
    let checks: PRChecks?

    var body: some View {
        if let counts = checks?.counts, let state = counts.state {
            HStack(spacing: 3) {
                state.glyph.image
                    .foregroundStyle(state.color)
                Text(verbatim: counts.fraction)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .help(Text(verbatim: counts.spokenSummary))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: counts.spokenSummary))
        }
    }
}
