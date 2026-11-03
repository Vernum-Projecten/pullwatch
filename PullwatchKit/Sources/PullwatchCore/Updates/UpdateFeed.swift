import Foundation

/// Waar de app zijn Sparkle-appcast vindt, en of updates in de app aan kunnen.
///
/// De releases zijn openbaar, dus er is geen token nodig: de appcast van de nieuwste release
/// staat op `https://github.com/<owner>/pullwatch/releases/latest/download/appcast.xml`. GitHub
/// rekent een pre-release (een testversie, `vX.Y.Z-beta.N`) daar niet toe; wie testversies wil,
/// krijgt de appcast van de nieuwste release met of zonder pre-release, via de API (ook zonder
/// token). De eigenaar komt uit de build-instelling `PW_RELEASES_OWNER` (Info.plist
/// `PWReleasesOwner`), zodat de fork en upstream alleen in hun configuratie verschillen.
public enum UpdateFeed {
    public static let repositoryName = "pullwatch"

    /// De appcast van de nieuwste gewone release.
    public static func latestURL(owner: String) -> URL {
        URL(string: "https://github.com/\(owner)/\(repositoryName)/releases/latest/download/appcast.xml")!
    }

    /// De appcast die Sparkle leest: die van de nieuwste release, en met `includeTestVersions` die
    /// van de nieuwste release of pre-release die een appcast heeft.
    public static func url(owner: String, includeTestVersions: Bool, http: any HTTPClient, now: Date = Date()) async throws -> URL {
        guard includeTestVersions else { return latestURL(owner: owner) }
        struct Release: Decodable {
            struct Asset: Decodable {
                let name: String
                let browserDownloadUrl: URL
            }
            let draft: Bool
            let assets: [Asset]
        }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(owner)/\(repositoryName)/releases?per_page=10")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await http.send(request)
        try HTTPStatus.check(response, now: now)
        // GitHub geeft de releases van nieuw naar oud.
        let releases = try JSONDecoding.decode([Release].self, from: data, snakeCase: true)
        let feed = releases.lazy.filter { !$0.draft }.compactMap { $0.assets.first { $0.name == "appcast.xml" }?.browserDownloadUrl }.first
        return feed ?? latestURL(owner: owner)
    }

    /// De update die Sparkle zou aanbieden, gelezen uit de appcast op `feed`; nil als deze build
    /// (`currentBuild`, CFBundleVersion) de nieuwste is die op deze macOS draait.
    public static func newest(
        feed: URL,
        currentBuild: String,
        includeTestVersions: Bool,
        system: OperatingSystemVersion,
        http: any HTTPClient,
        now: Date = Date()
    ) async throws -> AppcastItem? {
        let (data, response) = try await http.send(URLRequest(url: feed))
        try HTTPStatus.check(response, now: now)
        return Appcast.newest(
            in: Appcast.items(data),
            newerThan: currentBuild,
            channels: channels(includeTestVersions: includeTestVersions),
            system: system
        )
    }

    /// De Sparkle-kanalen die de app toelaat naast het standaardkanaal.
    public static func channels(includeTestVersions: Bool) -> Set<String> {
        includeTestVersions ? ["beta"] : []
    }

    /// Updates in de app kunnen alleen met Sparkle's openbare EdDSA-sleutel (`SUPublicEDKey`):
    /// 32 bytes in base64. Zonder sleutel (een build uit de broncode, of een fork zonder eigen
    /// sleutel) kan de app een update niet controleren, en valt hij terug op de melding met de
    /// downloadknop.
    public static func isEnabled(publicKey: String?) -> Bool {
        guard let key = publicKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty,
            let data = Data(base64Encoded: key)
        else { return false }
        return data.count == 32
    }
}
