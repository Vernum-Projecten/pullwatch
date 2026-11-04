import Foundation

/// Hoe een advies of package in de repo komt, voor het filter en de kolom Waar.
public enum DependencyOrigin: Int, CaseIterable, Comparable, Hashable, Sendable {
    /// Het project vraagt het zelf.
    case direct
    /// Alleen via een ander package.
    case transitive
    /// Niet te bepalen (geen manifest naast de lockfile).
    case unknown
    /// Alleen om te ontwikkelen en te testen.
    case dev

    public static func < (lhs: DependencyOrigin, rhs: DependencyOrigin) -> Bool { lhs.rawValue < rhs.rawValue }
}
