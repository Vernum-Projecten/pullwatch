import Foundation

/// Wat de versiecheck over eigen packages weet, per dependency-sleutel ("ecosysteem:naam"),
/// gemaakt door `VersionChecker.inHouseCheck(installs:published:accounts:)`.
struct InHouseCheck {
    /// Een install met het account en de eigenaar van de repository waarin hij staat: daartegen
    /// leest `InHouseEvidence.keepsPrivate` het register uit de lockfile (#216).
    struct Install {
        let dependency: Dependency
        let accountId: UUID
        /// Het deel van de repository voor de laatste "/" ("acme" in "acme/web", de groep bij GitLab,
        /// het project bij Azure DevOps).
        let owner: String

        init(_ dependency: Dependency, accountId: UUID, repo: String) {
            self.dependency = dependency
            self.accountId = accountId
            owner = repo.lastIndex(of: "/").map { String(repo[..<$0]) } ?? repo
        }

        var key: String { "\(dependency.ecosystem):\(dependency.name)" }
    }

    /// De eigen packages: metadata uit het eigen register, of zonder versies als alleen de lockfile
    /// ze eigen maakt (`InHousePackage.Status.unconfirmed`). Deze namen gaan nooit naar een publiek
    /// register, en alleen naar OSV als `InHousePackage.isPublicName`.
    var metadata: [String: PackageMetadata] = [:]
    /// Publieke packages waarvan een actief account een package met dezelfde naam publiceert,
    /// zonder bewijs dat een install daarvandaan komt (`PackageMetadata.alsoPublishedBy`).
    var namesakes: [String: InHousePackage] = [:]

    /// Of OSV naar deze sleutel gevraagd mag worden: elk publiek package, en een eigen package
    /// alleen als het publieke register de naam ook kent.
    func asksOSV(_ key: String) -> Bool {
        metadata[key]?.inHouse.map(\.isPublicName) ?? true
    }
}
