import Foundation

extension VersionReport {
    /// Neemt de eigen packages van `previous` over voor een account waarvan het register nu mislukte
    /// (netwerk, rate limit): één slechte dag laat de Packages-sectie niet leeg. Een account dat nu
    /// wel antwoord gaf, of geen recht meer heeft, krijgt het nieuwe resultaat. Stond de bron uit
    /// (geen enkel resultaat), dan blijft het leeg.
    public func carryingPublishedPackages(from previous: VersionReport?) -> VersionReport {
        guard let previous, publishedPackages.contains(where: \.isFailed) else { return self }
        let before = Dictionary(previous.publishedPackages.map { ($0.accountId, $0) }, uniquingKeysWith: { first, _ in first })
        let carried = publishedPackages.map { current in
            guard current.isFailed, let old = before[current.accountId], !old.isFailed else { return current }
            return old
        }
        return VersionReport(
            checkedAt: checkedAt, repos: repos, latestPackages: latestPackages, advisories: advisories, advisoryMisses: advisoryMisses,
            packageMetadata: packageMetadata, format: format, publishedPackages: carried
        )
    }

    /// Alle gepubliceerde packages van alle accounts samen.
    public var allPublishedPackages: [PublishedPackage] {
        publishedPackages.flatMap(\.result.packages)
    }
}

extension AccountPackages {
    var isFailed: Bool {
        if case .failed = result { return true }
        return false
    }
}
