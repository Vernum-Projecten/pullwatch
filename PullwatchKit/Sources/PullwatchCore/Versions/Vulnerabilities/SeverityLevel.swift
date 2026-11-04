import Foundation

/// Hoe ernstig een kwetsbaarheid of melding is, van onbekend tot kritiek.
public enum SeverityLevel: Int, CaseIterable, Comparable, Hashable, Sendable {
    case unknown, low, moderate, high, critical

    /// Uit "CRITICAL", "HIGH", "MODERATE"/"MEDIUM" of "LOW"; de rest is onbekend.
    public init(_ raw: String?) {
        switch raw?.uppercased() {
        case "CRITICAL": self = .critical
        case "HIGH": self = .high
        case "MODERATE", "MEDIUM": self = .moderate
        case "LOW": self = .low
        default: self = .unknown
        }
    }

    public static func < (lhs: SeverityLevel, rhs: SeverityLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}
