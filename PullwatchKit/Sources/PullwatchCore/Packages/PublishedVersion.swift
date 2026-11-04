public import Foundation

/// Eén gepubliceerde versie van een eigen package: een moment in de geschiedenis van de repository.
/// Alleen wat de Packages-sectie en de check op eigen packages nodig hebben; geen downloads.
public struct PublishedVersion: Codable, Hashable, Sendable {
    /// De versie zoals het register hem noemt ("2.3.0"); bij een container-image de tag.
    public let version: String
    public let publishedAt: Date?
    /// De pagina van deze versie bij het register.
    public let webURL: URL?
    /// De tag van de repository waar de versie bij hoort, als de dienst dat zegt.
    public let tag: String?
    /// De run of pipeline die hem publiceerde, als de dienst dat zegt.
    public let runURL: URL?
    /// Of de image van deze versie ook de tag `latest` draagt (alleen bij een container-image).
    public let isLatestTag: Bool

    public init(
        version: String, publishedAt: Date? = nil, webURL: URL? = nil, tag: String? = nil, runURL: URL? = nil, isLatestTag: Bool = false
    ) {
        self.version = version
        self.publishedAt = publishedAt
        self.webURL = webURL
        self.tag = tag
        self.runURL = runURL
        self.isLatestTag = isLatestTag
    }

    private enum CodingKeys: String, CodingKey {
        case version, publishedAt, webURL, tag, runURL, isLatestTag
    }

    /// Alles behalve de versie mag ontbreken, ook in gegevens van een oudere of nieuwere Pullwatch.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version)
        publishedAt = try? c.decodeIfPresent(Date.self, forKey: .publishedAt)
        webURL = try? c.decodeIfPresent(URL.self, forKey: .webURL)
        tag = try? c.decodeIfPresent(String.self, forKey: .tag)
        runURL = try? c.decodeIfPresent(URL.self, forKey: .runURL)
        isLatestTag = ((try? c.decodeIfPresent(Bool.self, forKey: .isLatestTag)) ?? nil) ?? false
    }
}
