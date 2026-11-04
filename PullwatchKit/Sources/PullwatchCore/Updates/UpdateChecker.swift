import Foundation

/// Een nieuwere Pullwatch op GitHub.
public struct AvailableUpdate: Equatable, Sendable {
    public let version: String
    /// Releasepagina met de release notes.
    public let pageURL: URL
    /// De DMG van de release; nil als die er (nog) niet bij staat.
    public let downloadURL: URL?
    /// Sparkle kan hem in de app installeren (de build heeft een openbare sleutel); anders
    /// download je de DMG zelf.
    public let installsInApp: Bool

    public init(version: String, pageURL: URL, downloadURL: URL?, installsInApp: Bool = false) {
        self.version = version
        self.pageURL = pageURL
        self.downloadURL = downloadURL
        self.installsInApp = installsInApp
    }

    /// Een update uit de appcast, die Sparkle installeert. Zonder releasepagina in de appcast
    /// (een zip buiten GitHub) wordt het de releaselijst van `owner`.
    public init(_ item: AppcastItem, owner: String) {
        self.init(
            version: item.displayVersion,
            pageURL: item.releasePage ?? UpdateChecker.releasesURL(owner: owner),
            downloadURL: nil,
            installsInApp: true
        )
    }
}

/// Kijkt naar de nieuwste release op GitHub (zonder token; publieke repo, 60 verzoeken per uur).
/// De terugval voor een build zonder Sparkle-sleutel (`UpdateFeed.isEnabled`): een melding met
/// een downloadknop voor de DMG.
public enum UpdateChecker {
    /// De eigenaar van de releases als de build er geen noemt (`PW_RELEASES_OWNER`).
    public static let defaultOwner = "alessandro823"

    static func latestReleaseURL(owner: String) -> URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(UpdateFeed.repositoryName)/releases/latest")!
    }

    public static func releasesURL(owner: String) -> URL {
        URL(string: "https://github.com/\(owner)/\(UpdateFeed.repositoryName)/releases")!
    }

    /// Eens per dag, zoals de versiecheck.
    public static let interval: TimeInterval = 24 * 3600

    /// De nieuwste release als die nieuwer is dan `current` ("0.3.0"), anders nil.
    public static func check(
        current: String,
        owner: String = defaultOwner,
        http: any HTTPClient,
        now: Date = Date()
    ) async throws -> AvailableUpdate? {
        struct Release: Decodable {
            struct Asset: Decodable {
                let name: String
                let browserDownloadUrl: URL
            }
            let tagName: String
            let htmlUrl: URL
            let assets: [Asset]
        }
        var request = URLRequest(url: latestReleaseURL(owner: owner))
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await http.send(request)
        try HTTPStatus.check(response, now: now)
        let release = try JSONDecoding.decode(Release.self, from: data, snakeCase: true)
        let version = release.tagName.droppingVersionPrefix
        guard isNewer(version, than: current) else { return nil }
        return AvailableUpdate(
            version: version,
            pageURL: release.htmlUrl,
            downloadURL: release.assets.first { $0.name.hasSuffix(".dmg") }?.browserDownloadUrl
        )
    }

    /// Alleen versienummers ("0.3.1"); pre-releases ("0.4.0-beta") tellen niet.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard candidate.allSatisfy({ $0.isNumber || $0 == "." }) else { return false }
        return VersionChecker.isOlder(current, than: candidate)
    }
}
