import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// De appcast zoals `generate_appcast` hem schrijft in release.yml: een gewone release, een
/// testversie op het `beta`-kanaal en een oude release in het oude attribuutformaat.
let sampleAppcast = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <title>Pullwatch</title>
        <item>
          <title>0.7.0</title>
          <sparkle:version>12</sparkle:version>
          <sparkle:shortVersionString>0.7.0</sparkle:shortVersionString>
          <sparkle:channel>beta</sparkle:channel>
          <sparkle:minimumSystemVersion>26.6</sparkle:minimumSystemVersion>
          <description><![CDATA[<ul><li>Iets nieuws</li></ul>]]></description>
          <enclosure url="https://github.com/alessandro823/pullwatch/releases/download/v0.7.0-beta.1/Pullwatch-0.7.0.zip" length="9123456" type="application/octet-stream" sparkle:edSignature="c2lnbmF0dXJl"/>
        </item>
        <item>
          <title>0.6.0</title>
          <sparkle:version>11</sparkle:version>
          <sparkle:shortVersionString>0.6.0</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>26.6</sparkle:minimumSystemVersion>
          <enclosure url="https://github.com/alessandro823/pullwatch/releases/download/v0.6.0/Pullwatch-0.6.0.zip" length="9000000" type="application/octet-stream" sparkle:edSignature="c2lnbmF0dXJl"/>
        </item>
        <item>
          <title>0.5.0</title>
          <enclosure url="https://example.org/Pullwatch-0.5.0.zip" sparkle:version="9" sparkle:shortVersionString="0.5.0" length="1"/>
        </item>
      </channel>
    </rss>
    """

@Suite struct AppcastTests {
    let tahoe = OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 0)

    var items: [AppcastItem] { Appcast.items(Data(sampleAppcast.utf8)) }

    @Test func readsEveryItem() throws {
        #expect(items.count == 3)
        let beta = try #require(items.first)
        #expect(beta.build == "12")
        #expect(beta.version == "0.7.0")
        #expect(beta.channel == "beta")
        #expect(beta.minimumSystemVersion == "26.6")
        #expect(beta.archiveURL?.lastPathComponent == "Pullwatch-0.7.0.zip")
    }

    @Test func readsTheOlderAttributeStyle() throws {
        let old = try #require(items.last)
        #expect(old.build == "9")
        #expect(old.version == "0.5.0")
        #expect(old.channel == nil)
        #expect(old.releasePage == nil)
    }

    @Test func findsTheReleasePageAndTag() throws {
        let beta = try #require(items.first)
        #expect(beta.tag == "v0.7.0-beta.1")
        #expect(beta.displayVersion == "0.7.0-beta.1")
        #expect(beta.releasePage?.absoluteString == "https://github.com/alessandro823/pullwatch/releases/tag/v0.7.0-beta.1")
    }

    @Test func unreadableFeedHasNoItems() {
        #expect(Appcast.items(Data("<rss><channel><item>".utf8)).isEmpty)
        #expect(Appcast.items(Data("not xml".utf8)).isEmpty)
        #expect(Appcast.items(Data("<rss/>".utf8)).isEmpty)
    }

    @Test func defaultChannelSkipsTestVersions() {
        let update = Appcast.newest(in: items, newerThan: "9", channels: [], system: tahoe)
        #expect(update?.build == "11")
    }

    @Test func betaChannelGetsTheTestVersion() {
        let update = Appcast.newest(in: items, newerThan: "9", channels: ["beta"], system: tahoe)
        #expect(update?.build == "12")
    }

    @Test func comparesAgainstTheBuildNumber() {
        // CFBundleVersion is 11: alleen de testversie is nieuwer, en die is uit zonder het kanaal.
        #expect(Appcast.newest(in: items, newerThan: "11", channels: [], system: tahoe) == nil)
        #expect(Appcast.newest(in: items, newerThan: "11", channels: ["beta"], system: tahoe)?.build == "12")
        #expect(Appcast.newest(in: items, newerThan: "12", channels: ["beta"], system: tahoe) == nil)
        #expect(Appcast.newest(in: items, newerThan: "100", channels: ["beta"], system: tahoe) == nil)
    }

    @Test func comparesNumerically() {
        #expect(Appcast.isNewer("10", than: "9"))
        #expect(!Appcast.isNewer("9", than: "10"))
        #expect(!Appcast.isNewer("9", than: "9"))
        #expect(Appcast.isNewer("1.2.10", than: "1.2.9"))
        #expect(!Appcast.isNewer("1.2", than: "1.2.0"))
        #expect(!Appcast.isNewer("", than: "1"))
    }

    @Test func skipsAnUpdateForANewerMacOS() {
        let older = OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 1)
        #expect(Appcast.newest(in: items, newerThan: "10", channels: ["beta"], system: older) == nil)
        // Zonder minimum draait de oude release overal.
        #expect(Appcast.newest(in: items, newerThan: "8", channels: [], system: older)?.build == "9")
        #expect(Appcast.runs(on: tahoe, minimum: "26.6"))
        #expect(Appcast.runs(on: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0), minimum: "26.6"))
        #expect(!Appcast.runs(on: tahoe, minimum: "26.6.1"))
    }
}

@Suite struct UpdateFeedTests {
    let tahoe = OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 0)

    @Test func readsTheLatestReleaseWithoutTheAPI() async throws {
        let http = MockHTTPClient()
        let url = try await UpdateFeed.url(owner: "alessandro823", includeTestVersions: false, http: http)
        #expect(url.absoluteString == "https://github.com/alessandro823/pullwatch/releases/latest/download/appcast.xml")
        #expect(http.requests.isEmpty)
    }

    @Test func theOwnerComesFromTheBuild() async throws {
        let url = try await UpdateFeed.url(owner: "Vernum-Projecten", includeTestVersions: false, http: MockHTTPClient())
        #expect(url.absoluteString == "https://github.com/Vernum-Projecten/pullwatch/releases/latest/download/appcast.xml")
        #expect(UpdateChecker.latestReleaseURL(owner: "Vernum-Projecten").absoluteString
            == "https://api.github.com/repos/Vernum-Projecten/pullwatch/releases/latest")
    }

    @Test func testVersionsReadTheNewestReleaseWithAnAppcast() async throws {
        let http = MockHTTPClient()
        http.on("repos/alessandro823/pullwatch/releases?", body: #"""
            [{"draft":true,"assets":[{"name":"appcast.xml","browser_download_url":"https://x/draft/appcast.xml"}]},
             {"draft":false,"assets":[{"name":"Pullwatch-0.7.0.dmg","browser_download_url":"https://x/old/Pullwatch.dmg"}]},
             {"draft":false,"assets":[{"name":"appcast.xml","browser_download_url":"https://github.com/alessandro823/pullwatch/releases/download/v0.7.0-beta.1/appcast.xml"}]},
             {"draft":false,"assets":[{"name":"appcast.xml","browser_download_url":"https://github.com/alessandro823/pullwatch/releases/download/v0.6.0/appcast.xml"}]}]
            """#)
        let url = try await UpdateFeed.url(owner: "alessandro823", includeTestVersions: true, http: http)
        #expect(url.absoluteString == "https://github.com/alessandro823/pullwatch/releases/download/v0.7.0-beta.1/appcast.xml")
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func testVersionsFallBackToTheLatestRelease() async throws {
        let http = MockHTTPClient()
        http.on("releases?", body: "[]")
        let url = try await UpdateFeed.url(owner: "alessandro823", includeTestVersions: true, http: http)
        #expect(url == UpdateFeed.latestURL(owner: "alessandro823"))
    }

    @Test func findsTheUpdateInTheFeed() async throws {
        let http = MockHTTPClient()
        http.on("latest/download/appcast.xml", body: sampleAppcast)
        let feed = UpdateFeed.latestURL(owner: "alessandro823")

        let stable = try await UpdateFeed.newest(feed: feed, currentBuild: "9", includeTestVersions: false, system: tahoe, http: http)
        #expect(stable?.build == "11")
        let beta = try await UpdateFeed.newest(feed: feed, currentBuild: "9", includeTestVersions: true, system: tahoe, http: http)
        #expect(beta?.build == "12")
        #expect(try await UpdateFeed.newest(feed: feed, currentBuild: "11", includeTestVersions: false, system: tahoe, http: http) == nil)
    }

    @Test func aMissingFeedIsAnError() async {
        let http = MockHTTPClient()
        http.on("appcast.xml", status: 404, body: "Not Found")
        await #expect(throws: ProviderError.self) {
            try await UpdateFeed.newest(
                feed: UpdateFeed.latestURL(owner: "alessandro823"), currentBuild: "9", includeTestVersions: false,
                system: tahoe, http: http)
        }
    }

    @Test func anUpdateFromTheFeedInstallsInTheApp() throws {
        let item = try #require(Appcast.items(Data(sampleAppcast.utf8)).dropFirst().first)
        let update = AvailableUpdate(item, owner: "alessandro823")
        #expect(update.version == "0.6.0")
        #expect(update.installsInApp)
        #expect(update.downloadURL == nil)
        #expect(update.pageURL.absoluteString == "https://github.com/alessandro823/pullwatch/releases/tag/v0.6.0")
    }

    @Test func disabledWithoutAKey() {
        #expect(!UpdateFeed.isEnabled(publicKey: nil))
        #expect(!UpdateFeed.isEnabled(publicKey: ""))
        #expect(!UpdateFeed.isEnabled(publicKey: "  "))
        // Een niet-uitgevulde build-instelling.
        #expect(!UpdateFeed.isEnabled(publicKey: "$(SPARKLE_PUBLIC_ED_KEY)"))
        // Geen 32 bytes.
        #expect(!UpdateFeed.isEnabled(publicKey: "c2lnbmF0dXJl"))
        // Een echte Ed25519-sleutel in base64 (FerroLICENCE's openbare sleutel als voorbeeld).
        #expect(UpdateFeed.isEnabled(publicKey: "CAMlb/hqw2ufjXJ22G5CxttIHhtwpCn/jE/KUSzkE34="))
    }

    @Test func testVersionsAreOffInAnOlderConfig() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"accounts":[],"pollInterval":120}"#.utf8))
        #expect(!config.includeTestVersions)
        var on = config
        on.includeTestVersions = true
        #expect(try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(on)).includeTestVersions)
    }

    @Test func channels() {
        #expect(UpdateFeed.channels(includeTestVersions: false).isEmpty)
        #expect(UpdateFeed.channels(includeTestVersions: true) == ["beta"])
    }
}
