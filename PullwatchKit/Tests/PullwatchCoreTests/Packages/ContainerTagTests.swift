import Foundation
import Testing
@testable import PullwatchCore

/// Welke tag van een image een versie is, welke zwevend en welke weg blijft; de tags komen uit
/// echte registers (ghcr.io: cosign, docker/metadata-action, Artifact Hub).
@Suite struct ContainerTagTests {
    @Test(arguments: [
        "1.2.3", "v1.2.3", "V2.0.0", "0.0", "0.4", "0.0.17", "21.0.0-rc9", "5.6.0-rc10", "0.2.0-rc1", "1.0.0-beta.2",
        "2024.11", "3", "1.2.3+build.7", "20261104",
    ])
    func `Reads a version tag`(tag: String) {
        #expect(ContainerTag(tag).kind == .version)
        #expect(ContainerTag(tag).version != nil)
    }

    @Test(arguments: [
        "sha256-7e0fd343419965e2b3c3151dbd7a601ac1e97f42caadbf2ef9d50f86883d1957",
        "sha256-7e0fd343419965e2b3c3151dbd7a601ac1e97f42caadbf2ef9d50f86883d1957.sig",
        "sha256-7e0fd343419965e2b3c3151dbd7a601ac1e97f42caadbf2ef9d50f86883d1957.att",
        "sha256-7e0fd343419965e2b3c3151dbd7a601ac1e97f42caadbf2ef9d50f86883d1957.sbom",
        "sha-466930c", "sha-6a043b4",
        "f83df34cc968f5e0f916834508336c8eeb4c9e41", "f83df34", "208262ad71f6addbb97c4b8025fcb9c95b3751d0",
        "1234567890123456789012345678901234567890",
        "artifacthub.io", "web.sig",
    ])
    func `Ignores digests, signatures, commits and metadata`(tag: String) {
        #expect(ContainerTag(tag).kind == .ignored)
    }

    @Test(arguments: ["latest", "main", "master", "edge", "nightly", "dev", "Latest", "pr-12", "staging", "feature-login"])
    func `A tag that is no version and says something floats`(tag: String) {
        #expect(ContainerTag(tag).kind == .floating)
    }

    @Test func `A pre-release ranks below its release and above the release before`() throws {
        let rc = try #require(ContainerTag("21.0.0-rc9").version)
        #expect(rc < (try #require(ContainerTag("21.0.0").version)))
        #expect(rc > (try #require(ContainerTag("20.0.0").version)))
        #expect(ContainerTag("v1.10.0").isBetterVersion(than: ContainerTag("1.9.0")))
    }

    @Test func `Of two names for one version the precise one wins`() {
        #expect(ContainerTag("0.4.0").isBetterVersion(than: ContainerTag("0.4")))
        #expect(!ContainerTag("0.4").isBetterVersion(than: ContainerTag("0.4.0")))
    }
}
