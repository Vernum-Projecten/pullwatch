import PullwatchCore
import SwiftUI

/// De checks van een PR zoals in de PR-lijst van GitHub: de Octicon van de stand in zijn kleur
/// (een vinkje, een kruis of een stip) en de telling "4/8", zonder woorden. De woorden staan in
/// de tooltip en in VoiceOver. Zonder checks, of zonder toestemming om ze te lezen, niets; ook
/// niets als de bron CI-checks uit staat (Instellingen, Bronnen), want eerder opgehaalde checks
/// zijn dan niet meer actueel.
///
/// Leest zelf geen model uit de environment: hij staat in cellen van een `Table`, en AppKit
/// tekent zo'n cel soms buiten de environment van het venster (dan stopt SwiftUI de app met
/// "No Observable object of type AccountsModel found"). De view erboven geeft daarom mee of de
/// bron aan staat.
struct ChecksBadge: View {
    let checks: PRChecks?
    /// De bron CI-checks staat aan (`config.isEnabled(.ciChecks)`).
    let isEnabled: Bool

    var body: some View {
        if isEnabled, let counts = checks?.counts, let state = counts.state {
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
