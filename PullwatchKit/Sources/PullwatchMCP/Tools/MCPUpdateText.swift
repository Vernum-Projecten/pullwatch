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

    /// Waarom de status onbekend is, als woord voor de uitvoer.
    static let unknownReasons = ["no_latest_version", "latest_not_looked_up", "unreadable_version", "no_requirement", "unreadable_requirement"]

    static func reason(_ reason: PackageUpdate.UnknownReason?) -> String? {
        switch reason {
        case .noLatestVersion?: "no_latest_version"
        case .latestNotLookedUp?: "latest_not_looked_up"
        case .unreadableVersion?: "unreadable_version"
        case .noRequirement?: "no_requirement"
        case .unreadableRequirement?: "unreadable_requirement"
        case nil: nil
        }
    }

    /// Waarom de status onbekend is, als bijzin; `parent` is de directe ouder van een transitieve install.
    static func cause(_ reason: PackageUpdate.UnknownReason, parent: String?) -> String {
        switch reason {
        case .noLatestVersion:
            "the registry gave no latest version"
        case .latestNotLookedUp:
            "Pullwatch looks up the latest version only for packages the repository asks for itself"
        case .unreadableVersion:
            "the installed or latest version is not a version number Pullwatch can compare"
        case .noRequirement:
            parent.map { "the range \($0) asks for is not known" } ?? "no requested range was found in the manifest"
        case .unreadableRequirement(let requested):
            "the requested range \(requested) could not be read"
        }
    }
}
