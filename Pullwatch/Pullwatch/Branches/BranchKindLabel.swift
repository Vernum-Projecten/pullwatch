import PullwatchCore
import SwiftUI

/// De kolom Commits van een push: "+4" bij nieuwe commits, een pill bij een force-push of een
/// nieuwe branch, en leeg bij een seed-rij of als het aantal onbekend is. Leest geen model uit de
/// environment, want hij staat in een cel van een tabel.
struct BranchKindLabel: View {
    let kind: BranchPush.Kind
    let commits: Int?

    var body: some View {
        switch kind {
        case .forcePush:
            Pill(text: "Force-push", tint: .orange)
        case .newBranch:
            Pill(text: "Nieuwe branch", tint: .green)
        case .push:
            if let commits, commits > 0 {
                Text(verbatim: "+\(commits)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("\(commits) nieuwe commits", comment: "Aantal commits in een push"))
            }
        case .recent:
            EmptyView()
        }
    }
}
