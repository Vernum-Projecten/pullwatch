import Foundation
@testable import PullwatchCore

// Gedeeld door de tests van lockfiles en manifesten.

/// Alle installs uit deze bestanden (pad → inhoud), in de volgorde van de paden.
func installs(_ files: [String: String]) -> [Dependency] {
    DependencyDetector.installs(files.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }).dependencies
}

/// "naam@versie workspace scope soort via" per install, gesorteerd.
func describe(_ dependencies: [Dependency]) -> [String] {
    dependencies.map { d in
        let workspace = d.workspace.isEmpty ? "." : d.workspace
        return "\(d.name)@\(d.version) \(workspace) \(d.scope.rawValue) \(d.kind.rawValue) \(d.via.joined(separator: ">"))"
            .trimmingCharacters(in: .whitespaces)
    }.sorted()
}
