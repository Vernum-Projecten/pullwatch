import Foundation
import Testing
@testable import PullwatchCore

/// De versies van een image uit zijn tags, met ingekorte echte tag-mixen van ghcr.io (nieuwste
/// eerst, zoals GitHub ze geeft).
@Suite struct ContainerVersionsTests {
    func image(_ tags: [String], _ day: Int) -> ContainerVersions.Image {
        ContainerVersions.Image(tags: tags, publishedAt: Date.testDay(day))
    }

    /// Een release met cosign-handtekeningen (`sha256-<digest>`) en digests zonder tag erboven.
    var bridge: [ContainerVersions.Image] {
        [
            image(["sha256-7e0fd343419965e2b3c3151dbd7a601ac1e97f42caadbf2ef9d50f86883d1957"], 30),
            image([], 30),
            image(["0.0.17", "latest", "0.0"], 29),
            image(["sha256-4a69b5a9388a8a2edabbe84ead3f62cb3009aab0fa089a98cb20e84c265b2f27"], 28),
            image(["0.0.15"], 27),
            image(["0.0.14"], 20),
        ]
    }

    @Test func `The highest version tag is the latest version, never a signature`() {
        let found = ContainerVersions(images: bridge)

        #expect(found.latestVersion == "0.0.17")
        #expect(found.latestKind == .version)
        #expect(found.publishedAt == Date.testDay(29))
        #expect(found.versions.map(\.version) == ["0.0.17", "0.0.15", "0.0.14"])
        #expect(found.versions.map(\.isLatestTag) == [true, false, false])
        #expect(found.latestTag == .onLatestVersion)
    }

    @Test func `A Helm chart ignores artifacthub.io and orders pre-releases by version`() {
        let chart = [
            image(["artifacthub.io"], 30),
            image(["sha256-96229580887ea37960c3f59a698bc3710597a38b25f7878ce7c1bc5bf431d53a"], 30),
            image(["21.0.0-rc9"], 30),
            image(["21.0.0-rc7"], 29),
            image(["20.0.0"], 25),
            image(["14.0.1"], 20),
        ]
        let found = ContainerVersions(images: chart)

        #expect(found.latestVersion == "21.0.0-rc9", "op versievolgorde, een rc boven de vorige release")
        #expect(found.versions.map(\.version) == ["21.0.0-rc9", "21.0.0-rc7", "20.0.0", "14.0.1"])
        #expect(found.latestTag == .absent)
    }

    @Test func `Order is by version, not by date`() {
        let found = ContainerVersions(images: [image(["1.4.3"], 30), image(["2.0.0"], 10)])

        #expect(found.latestVersion == "2.0.0")
        #expect(found.publishedAt == Date.testDay(10), "de datum van die versie")
    }

    @Test func `Several names for one image show the most precise version`() {
        let found = ContainerVersions(images: [
            image(["sha-6a043b4", "0.4", "0.4.0", "latest"], 30),
            image(["sha-bfcb62d", "0.3.3", "0.3"], 29),
        ])

        #expect(found.latestVersion == "0.4.0")
        #expect(found.versions.map(\.version) == ["0.4.0", "0.3.3"])
    }

    @Test func `Latest on a newer build without a version tag`() {
        let found = ContainerVersions(images: [image(["sha-466930c", "latest"], 30), image(["0.1.1"], 20)])

        #expect(found.latestVersion == "0.1.1")
        #expect(found.latestTag == .unversionedBuild)
        #expect(found.versions.map(\.isLatestTag) == [false])
    }

    @Test func `Latest on an image with another version`() {
        let found = ContainerVersions(images: [image(["1.0.0-rc1"], 30), image(["0.9.0", "latest"], 20)])

        #expect(found.latestVersion == "1.0.0-rc1")
        #expect(found.latestTag == .otherVersion("0.9.0"))
        #expect(found.versions.map(\.isLatestTag) == [false, true])
    }

    @Test func `Only commit tags and main fall back to the newest floating tag`() {
        let found = ContainerVersions(images: [
            image(["sha256-6ae52104050e88a57d380b6d61a14db91ba985bb08854faac4daa6d1f17d8c0a"], 30),
            image(["sha-466930c", "main"], 29),
            image(["sha-659ca4a"], 28),
        ])

        #expect(found.latestVersion == "main")
        #expect(found.latestKind == .floatingTag)
        #expect(found.publishedAt == Date.testDay(29))
        #expect(found.versions.isEmpty)
    }

    @Test func `Commit tags with latest fall back to latest`() {
        let found = ContainerVersions(images: [
            image(["f83df34cc968f5e0f916834508336c8eeb4c9e41", "latest"], 30),
            image(["2c62de91744b01c2c4e1b400b076260a0dca7777"], 29),
        ])

        #expect(found.latestVersion == "latest")
        #expect(found.latestKind == .floatingTag)
    }

    @Test func `A floating fallback prefers a branch over latest on the same image`() {
        #expect(ContainerVersions(images: [image(["latest", "main"], 30)]).latestVersion == "main")
    }

    @Test func `Images without any tag are untagged`() {
        let found = ContainerVersions(images: [image([], 30), image(["sha256-4cdf8d4b4c4d626b99a3929a363198067f87ac70875f4ce6db1d0614884f12af"], 29)])

        #expect(found.latestVersion == nil)
        #expect(found.latestKind == .untagged)
        #expect(found.publishedAt == Date.testDay(30))
    }

    @Test func `No images is unknown, not untagged`() {
        let found = ContainerVersions(images: [])

        #expect(found.latestVersion == nil)
        #expect(found.latestKind == .version)
    }

    @Test func `Keeps at most ten recent versions`() {
        let images = (0..<15).map { image(["1.\(20 - $0).0"], 30 - $0) }

        #expect(ContainerVersions(images: images).versions.count == PublishedPackage.recentVersionLimit)
        #expect(ContainerVersions.versionTaggedCount(images + [image(["main"], 1)]) == 15)
    }
}

extension Date {
    /// Een dag in november 2026, voor datums in een fixture.
    fileprivate static func testDay(_ day: Int) -> Date {
        Date(timeIntervalSince1970: 1_792_000_000 + Double(day) * 86_400)
    }
}
