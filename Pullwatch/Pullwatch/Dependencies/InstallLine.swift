import AppKit
import PullwatchCore
import SwiftUI

/// Eén install onder een advies of package: versie, workspace en keten. VoiceOver leest de keten
/// als "via express, dan body-parser".
struct InstallLine: View {
    /// nil zonder versie (een tabelcel met de versie in een eigen kolom).
    var version: String? = nil
    var fixedIn: String? = nil
    /// nil als de workspace niet genoemd hoeft te worden.
    var workspace: String? = nil
    let scope: DependencyScope
    let via: [String]
    var isDev = false
    var font: Font = .caption

    var body: some View {
        HStack(spacing: 6) {
            if let version {
                Text(verbatim: fixedIn.map { "\(version) → \($0)" } ?? version)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            if let workspace {
                Label(Workspace.name(workspace), systemImage: "folder")
                    .labelStyle(.titleAndIcon)
            }
            if let provenance = Provenance.text(scope: scope, via: via) {
                Text(verbatim: provenance)
                    .accessibilityLabel(Text(verbatim: Provenance.spoken(scope: scope, via: via) ?? provenance))
            }
            if isDev {
                Pill(text: "Dev", tint: .secondary)
            }
        }
        .font(font)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// Hoe een install in een project komt, als tekst.
enum Provenance {
    /// "Direct", "via express → body-parser" of "Transitief"; nil als het niet te bepalen is.
    static func text(scope: DependencyScope, via: [String]) -> String? {
        switch scope {
        case .direct: String(localized: "Direct")
        case .transitive where !via.isEmpty: chain(via)
        case .transitive: String(localized: "Transitief")
        case .unknown: nil
        }
    }

    /// "via express → body-parser".
    static func chain(_ via: [String]) -> String {
        String(localized: "via \(via.joined(separator: " → "))", comment: "Keten van packages, bv. express → body-parser")
    }

    /// Voor VoiceOver: "via express, dan body-parser".
    static func spoken(scope: DependencyScope, via: [String]) -> String? {
        guard scope == .transitive, let first = via.first else { return text(scope: scope, via: via) }
        let chain = via.dropFirst().reduce(first) { chain, next in
            String(localized: "\(chain), dan \(next)", comment: "Voorgelezen keten van packages: wat er al staat, het volgende package")
        }
        return String(localized: "via \(chain)", comment: "Keten van packages, bv. express → body-parser")
    }

    /// Eén regel voor een melding of het klembord: hoe en waar, en of het alleen dev is.
    static func line(scope: DependencyScope, via: [String], workspace: String, kind: DependencyKind) -> String? {
        let place: String?
        switch scope {
        case .direct:
            place = workspace.isEmpty ? String(localized: "Direct") : String(localized: "Direct in \(workspace)", comment: "Workspace, bv. packages/web")
        case .transitive where !via.isEmpty:
            place = workspace.isEmpty
                ? chain(via)
                : String(localized: "via \(via.joined(separator: " → ")) in \(workspace)", comment: "Keten van packages, workspace")
        case .transitive:
            place = workspace.isEmpty ? String(localized: "Transitief") : String(localized: "Transitief in \(workspace)", comment: "Workspace, bv. packages/web")
        case .unknown:
            place = workspace.isEmpty ? nil : String(localized: "In \(workspace)", comment: "Workspace, bv. packages/web")
        }
        let dev = kind == .dev ? String(localized: "Alleen dev") : nil
        let parts = [place, dev].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// De naam van een workspace: "Root" voor de hoofdmap.
enum Workspace {
    static func name(_ workspace: String) -> String {
        workspace.isEmpty ? String(localized: "Root", comment: "De hoofdmap van een repo, als workspace") : workspace
    }
}
