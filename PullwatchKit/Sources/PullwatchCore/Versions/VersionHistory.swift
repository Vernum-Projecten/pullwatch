import Foundation

/// Compacte stand van één repo bij een versiecheck, voor statistieken door de tijd.
public struct RepoSnapshot: Codable, Equatable, Sendable {
    /// Zelfde als `RepoVersions.id`.
    public let id: String
    /// Onderdeel (label) → gevonden versie.
    public let components: [String: String]
    public let statuses: [String: VersionStatus]
    /// Ernst ("HIGH", …, "?" zonder ernst) → aantal kwetsbaarheden.
    public let vulnerabilities: [String: Int]
    /// Runtimes en packages waarvoor een nieuwere versie bestaat.
    public let packageUpdates: Int
}

public struct VersionSnapshot: Codable, Equatable, Sendable {
    public let checkedAt: Date
    public let repos: [RepoSnapshot]
}

/// Momentopnames van elke volledige versiecheck, oudste eerst.
public struct VersionHistory: Codable, Equatable, Sendable {
    /// Ongeveer twee jaar bij één check per dag.
    static let maxSnapshots = 730

    public private(set) var snapshots: [VersionSnapshot] = []

    public init() {}

    public mutating func append(_ report: VersionReport) {
        let summaries = report.packageSummaries()
        let repos = report.repos.filter { $0.repo.contains("/") && $0.error == nil }.map { repo in
            RepoSnapshot(
                id: repo.id,
                components: Dictionary(repo.components.map { ($0.label, $0.version) }, uniquingKeysWith: { first, _ in first }),
                statuses: Dictionary(repo.components.map { ($0.label, $0.status) }, uniquingKeysWith: { first, _ in first }),
                vulnerabilities: Dictionary(grouping: repo.vulnerabilities, by: { $0.severity ?? "?" }).mapValues(\.count),
                packageUpdates: summaries.filter { $0.behind.contains { $0.repoId == repo.id } }.count
            )
        }
        snapshots.append(VersionSnapshot(checkedAt: report.checkedAt, repos: repos))
        if snapshots.count > Self.maxSnapshots {
            snapshots.removeFirst(snapshots.count - Self.maxSnapshots)
        }
    }
}
