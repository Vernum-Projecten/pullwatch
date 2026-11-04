import AppKit
import PullwatchCore
import SwiftUI

/// Symbool en woord van een ernst; onbekend zonder kleur.
struct SeverityLabel: View {
    let level: SeverityLevel

    var body: some View {
        Label {
            Text(level.label)
                .foregroundStyle(level == .unknown ? .secondary : .primary)
        } icon: {
            Image(systemName: level.symbol)
                .foregroundStyle(level.color)
        }
        .lineLimit(1)
    }
}

extension SeverityLevel {
    var label: LocalizedStringResource {
        switch self {
        case .critical: "Kritiek"
        case .high: "Hoog"
        case .moderate: "Gemiddeld"
        case .low: "Laag"
        case .unknown: "Onbekend"
        }
    }

    /// Elke ernst een eigen vorm, zodat de kleur niet de enige aanwijzing is.
    var symbol: String {
        switch self {
        case .critical: "exclamationmark.octagon.fill"
        case .high: "exclamationmark.triangle.fill"
        case .moderate: "exclamationmark.circle.fill"
        case .low: "info.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .critical: .red
        case .high: .orange
        case .moderate: .yellow
        case .low: .blue
        case .unknown: .secondary
        }
    }
}
