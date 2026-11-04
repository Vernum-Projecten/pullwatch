public import Foundation

/// De versies van een container-image (of OCI-Helm-chart) uit zijn tags. In het register is een
/// versie een digest met nul of meer tags; wat een mens de versie noemt, is de hoogste tag die als
/// versie leest (`ContainerTag`), nooit een digest, handtekening of commit.
///
/// - Nieuwste versie: de hoogste stabiele versietag over alle gelezen images, op versievolgorde
///   (niet op datum), met de datum van zijn image; zonder stabiele versie de hoogste pre-release.
/// - Recente versies: de nieuwste images met een versietag, hooguit `recentVersionLimit`, elk met
///   zijn hoogste versietag, en `isLatestTag` op de image die ook `latest` draagt.
/// - Geen versietag: de nieuwste zwevende tag (`main`), als `.floatingTag`; geen enkele tag:
///   `.untagged`.
public struct ContainerVersions: Hashable, Sendable {
    /// Eén image (digest) met zijn tags, zoals het register hem noemt.
    public struct Image: Hashable, Sendable {
        public let tags: [String]
        public let publishedAt: Date?
        public let webURL: URL?

        public init(tags: [String], publishedAt: Date?, webURL: URL? = nil) {
            self.tags = tags
            self.publishedAt = publishedAt
            self.webURL = webURL
        }

        /// De hoogste versietag, en bij gelijke versies de meest precieze; nil zonder versietag.
        var versionTag: ContainerTag? {
            tags.map(ContainerTag.init).filter { $0.kind == .version }.max { $1.isBetterVersion(than: $0) }
        }

        var carriesLatest: Bool { tags.contains(ContainerTag.latest) }
    }

    public let latestVersion: String?
    public let publishedAt: Date?
    public let latestKind: PublishedPackage.LatestKind
    /// Waar `latest` naar wijst (zie `PublishedPackage.latestTag`).
    public let latestTag: PublishedPackage.LatestTag
    public let versions: [PublishedVersion]

    /// - Parameter images: nieuwste eerst, zoals het register ze geeft.
    public init(images: [Image]) {
        let tagged = images.compactMap { image in image.versionTag.map { (image: image, tag: $0) } }
        versions = tagged.prefix(PublishedPackage.recentVersionLimit).map { item in
            PublishedVersion(
                version: item.tag.name, publishedAt: item.image.publishedAt, webURL: item.image.webURL,
                isLatestTag: item.image.carriesLatest
            )
        }
        let latestImage = images.first(where: \.carriesLatest)
        // De hoogste stabiele release, zoals Renovate en Dependabot; alleen zonder stabiele
        // versietag de hoogste pre-release.
        let stable = tagged.filter { $0.tag.version?.isPrerelease == false }
        if let best = (stable.isEmpty ? tagged : stable).max(by: { $1.tag.isBetterVersion(than: $0.tag) }) {
            latestVersion = best.tag.name
            publishedAt = best.image.publishedAt
            latestKind = .version
            if let latestImage {
                let pointsAt = latestImage.versionTag?.name
                latestTag = pointsAt == best.tag.name ? .onLatestVersion : pointsAt.map { .otherVersion($0) } ?? .unversionedBuild
            } else {
                latestTag = .absent
            }
            return
        }
        latestTag = latestImage == nil ? .absent : .unversionedBuild
        // Geen versietag: de nieuwste zwevende tag, liever een branch dan `latest` op dezelfde image.
        for image in images {
            let floating = image.tags.map(ContainerTag.init).filter { $0.kind == .floating }
            guard let tag = floating.first(where: { $0.name != ContainerTag.latest }) ?? floating.first else { continue }
            latestVersion = tag.name
            publishedAt = image.publishedAt
            latestKind = .floatingTag
            return
        }
        latestVersion = nil
        publishedAt = images.first?.publishedAt
        latestKind = images.isEmpty ? .version : .untagged
    }

    /// Hoeveel images een versietag hebben: genoeg (`recentVersionLimit`) en het lezen van meer
    /// pagina's kan stoppen.
    public static func versionTaggedCount(_ images: [Image]) -> Int {
        images.count { $0.versionTag != nil }
    }
}
