import Foundation

/// Wat de versiecheck over eigen packages weet, per dependency-sleutel ("ecosysteem:naam"),
/// gemaakt door `VersionChecker.inHouseCheck(dependencies:published:accounts:)`.
struct InHouseCheck {
    /// De eigen packages: metadata uit het eigen register. Deze namen gaan nooit naar een publiek
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
