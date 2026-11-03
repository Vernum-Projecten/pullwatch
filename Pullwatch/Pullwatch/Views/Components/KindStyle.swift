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

extension ItemKind {
    var color: Color {
        switch self {
        case .pullRequest: .blue
        case .tag: .orange
        }
    }

    var symbol: String {
        switch self {
        case .pullRequest: "arrow.triangle.pull"
        case .tag: "tag"
        }
    }

    var pillText: LocalizedStringResource {
        switch self {
        case .pullRequest: "PR"
        case .tag: "Tag"
        }
    }
}

extension PRState {
    var color: Color {
        switch self {
        case .open: .green
        case .merged: .purple
        case .closed: .gray
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .open: "Open"
        case .merged: "Gemerged"
        case .closed: "Gesloten"
        }
    }
}
