import PullwatchCore
import SwiftUI

/// Kleine gekleurde pill: soort, PR-status, versiestatus, ernst, plek van een kwetsbaarheid of
/// een kort label in de repolijst. De enige pill in de app, zodat ze er overal hetzelfde uitzien.
struct Pill: View {
    let text: LocalizedStringResource
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(tint.opacity(0.15), in: Capsule())
    }
}
