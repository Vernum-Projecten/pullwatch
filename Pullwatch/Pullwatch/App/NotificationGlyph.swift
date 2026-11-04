import PullwatchCore
import SwiftUI

/// Het teken van een soort melding als bijlage als er geen profielfoto is: de Octicon van de PR
/// zoals in de lijsten, of een SF Symbol, in de kleur van de soort.
nonisolated enum NotificationGlyph: Hashable, Sendable, CaseIterable {
    case pullRequest, merged, checksFailed, release, tag, vulnerability, securityAlert, packageUpdate

    init?(kind: NotificationKind) {
        switch kind {
        case .pullRequest: self = .pullRequest
        case .merged: self = .merged
        case .checksFailed: self = .checksFailed
        case .release: self = .release
        case .tag: self = .tag
        case .vulnerability: self = .vulnerability
        case .securityAlert: self = .securityAlert
        case .packageUpdate: self = .packageUpdate
        // Het icoon van Pullwatch staat er al; een tweede plaatje zegt niets.
        case .appUpdate, .account: return nil
        }
    }

    var glyph: Glyph {
        switch self {
        case .pullRequest: PRStatus.open.glyph
        case .merged: PRStatus.merged.glyph
        case .checksFailed: CheckState.failed.glyph
        case .release: .system("shippingbox.fill")
        case .tag: ItemKind.tag.glyph
        case .vulnerability: .system("exclamationmark.shield.fill")
        case .securityAlert: .system("shield.lefthalf.filled")
        case .packageUpdate: .system("arrow.up.circle.fill")
        }
    }

    var color: Color {
        switch self {
        case .pullRequest: PRStatus.open.color
        case .merged: PRStatus.merged.color
        case .checksFailed: CheckState.failed.color
        case .release, .tag: ItemKind.tag.color
        case .vulnerability: .red
        case .securityAlert: .orange
        case .packageUpdate: .blue
        }
    }

    @MainActor var view: some View {
        glyph.image
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .padding(10)
            .frame(width: 64, height: 64)
            .background(color.opacity(0.15), in: .rect(cornerRadius: 14))
    }
}
