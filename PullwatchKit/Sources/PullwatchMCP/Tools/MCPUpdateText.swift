import PullwatchCore

/// De vaste woorden waarmee de tools de stand van een update noemen.
enum MCPUpdateText {
    /// up_to_date, within_range, needs_manifest_change, blocked of unknown.
    static func status(_ status: PackageUpdate.Status) -> String {
        switch status {
        case .upToDate: "up_to_date"
        case .withinRange: "within_range"
        case .needsManifestChange: "needs_manifest_change"
        case .blockedByPackage, .blockedByPeer, .blockedByRuntime: "blocked"
        case .unknown: "unknown"
        }
    }

    /// patch, minor of major; nil zonder stap.
    static func step(_ step: UpdateStep?) -> String? {
        step?.rawValue
    }
}
