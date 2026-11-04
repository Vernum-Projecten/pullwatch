import Foundation
import MCP
import PullwatchCore
import PullwatchMCP
import Testing

/// `explain_update` en `get_repository_report` over een Cargo-workspace: een transitieve crate met
/// een kwetsbaarheid, een directe crate binnen zijn bereik en een zonder bereik.
@Suite struct CargoToolsTests {
    let harness: ToolHarness

    static let rustlsVulnerability = Vulnerability(
        id: "GHSA-2mjx-qc3c-rqvc", cve: nil, summary: "rustls bug", severity: "HIGH", ecosystem: "crates.io", package: "rustls",
        version: "0.23.44", fixedIn: "0.23.45", source: "Cargo.lock", workspace: "", scope: .transitive, via: ["reqwest"]
    )

    static func report(format: Int = VersionReport.currentFormat) -> VersionReport {
        let checkedAt = FakeDataSource.checkedAt
        return VersionReport(
            checkedAt: checkedAt,
            repos: [RepoVersions(
                accountId: FakeDataSource.gitHubId, repo: "acme/api", components: [],
                vulnerabilities: [rustlsVulnerability],
                packages: [
                    PackageUse(ecosystem: "crates.io", name: "fhir-types", installs: [
                        PackageInstall(version: "0.1.85", workspace: "", scope: .direct, source: "Cargo.lock", requested: "0.1.85"),
                    ]),
                    PackageUse(ecosystem: "crates.io", name: "reqwest", installs: [
                        PackageInstall(version: "0.12.5", workspace: "", scope: .direct, source: "Cargo.lock", requested: "0.12"),
                    ]),
                    PackageUse(ecosystem: "crates.io", name: "thirtyfour", installs: [
                        PackageInstall(version: "0.37.5", workspace: "", scope: .direct, kind: .dev, source: "Cargo.lock"),
                    ]),
                ],
                otherPackages: [
                    PackageUse(ecosystem: "crates.io", name: "rustls", installs: [
                        PackageInstall(version: "0.23.44", workspace: "", scope: .transitive, via: ["reqwest"], source: "Cargo.lock"),
                    ]),
                ]
            )],
            latestPackages: [
                "crates.io:fhir-types": PackageLatest(version: "0.1.128", seenAt: checkedAt),
                "crates.io:reqwest": PackageLatest(version: "0.12.24", seenAt: checkedAt),
                "crates.io:thirtyfour": PackageLatest(version: "0.37.6", seenAt: checkedAt),
            ],
            packageMetadata: [
                "crates.io:reqwest": PackageMetadata(latest: "0.12.24", versions: [
                    "0.12.5": VersionMetadata(dependencies: ["rustls": "^0.23.10"]),
                    "0.12.24": VersionMetadata(dependencies: ["rustls": "^0.23.31"]),
                ]),
            ],
            format: format
        )
    }

    init() {
        var source = FakeDataSource()
        source.report = Self.report()
        harness = ToolHarness(source: source)
    }

    // MARK: - explain_update

    @Test func `Explains a transitive crate with what its fix changes`() async throws {
        let output = try await harness.output("explain_update", ["repo": "acme/api", "package": "rustls"])

        #expect(output["ecosystem"] == "cargo")
        #expect(output["latest"] == nil)
        let install = try #require(output["installs"]?.objects.first)
        #expect(install["version"] == "0.23.44")
        #expect(install["scope"] == "transitive")
        #expect(install["via"] == ["reqwest"])
        #expect(install["requested"] == "^0.23.10")
        #expect(install["update"] == "unknown")
        #expect(install["unknown_reason"] == "latest_not_looked_up")
        #expect(install["explanation"] == .string(
            "rustls 0.23.44 in the root comes in through reqwest; reqwest asks for rustls ^0.23.10. "
                + "Its latest version is not known: Pullwatch looks up the latest version only for packages the repository asks for itself. "
                + "To fix GHSA-2mjx-qc3c-rqvc, rustls 0.23.45 is within the range ^0.23.10 that reqwest asks for, "
                + "so only the lock file changes (cargo update -p rustls)."
        ))
        #expect(output["vulnerabilities"] == [[
            "id": "GHSA-2mjx-qc3c-rqvc", "severity": "high", "fixed_in": "0.23.45",
            "fix": "Update rustls to 0.23.45 (within the requested range).",
        ]])
    }

    @Test func `A transitive fix the parent does not allow names the parent version and its range`() async throws {
        var source = FakeDataSource()
        let base = Self.report()
        var metadata = base.packageMetadata
        metadata["crates.io:reqwest"] = PackageMetadata(latest: "0.12.24", versions: [
            "0.12.5": VersionMetadata(dependencies: ["rustls": "=0.23.44"]),
            "0.12.24": VersionMetadata(dependencies: ["rustls": "^0.23.31"]),
        ])
        source.report = VersionReport(checkedAt: base.checkedAt, repos: base.repos, latestPackages: base.latestPackages, packageMetadata: metadata)
        let output = try await ToolHarness(source: source).output("explain_update", ["repo": "acme/api", "package": "rustls"])

        let explanation = try #require(output["installs"]?.objects.first?["explanation"]?.stringValue)
        #expect(explanation.hasSuffix(
            "To fix GHSA-2mjx-qc3c-rqvc, update reqwest to 0.12.24 first: it asks for rustls =0.23.44, which does not allow 0.23.45. "
                + "0.12.24 is within the range 0.12 the manifest asks for reqwest, so only the lock file changes."
        ))
    }

    @Test func `A direct crate with a requirement is within range`() async throws {
        let output = try await harness.output("explain_update", ["repo": "acme/api", "package": "fhir-types"])

        let install = try #require(output["installs"]?.objects.first)
        #expect(install["requested"] == "0.1.85")
        #expect(install["update"] == "within_range")
        #expect(install["unknown_reason"] == nil)
        #expect(install["explanation"] == "fhir-types 0.1.128 is within the requested range 0.1.85; only the lock file changes.")
    }

    @Test func `An unknown status names the missing requirement, not a missing latest version`() async throws {
        let output = try await harness.output("explain_update", ["repo": "acme/api", "package": "thirtyfour"])

        #expect(output["latest"] == "0.37.6")
        let install = try #require(output["installs"]?.objects.first)
        #expect(install["update"] == "unknown")
        #expect(install["unknown_reason"] == "no_requirement")
        #expect(install["explanation"] == .string(
            "Pullwatch cannot tell whether thirtyfour 0.37.5 in the root can be updated: no requested range was found in the manifest."
        ))
    }

    @Test func `A report from an older check says why a package is missing`() async throws {
        var source = FakeDataSource()
        source.report = Self.report(format: 1)
        let message = try await ToolHarness(source: source).error("explain_update", ["repo": "acme/api", "package": "ring"])

        #expect(message == "acme/api does not use a package named ring in Pullwatch's last check. That check was made by an older version of "
            + "Pullwatch, which kept only the direct packages; Pullwatch checks again by itself. get_repository_report lists its packages.")
    }

    // MARK: - get_repository_report

    @Test func `The report lists transitive crates with their chain`() async throws {
        let output = try await harness.output("get_repository_report", ["repo": "acme/api"])

        #expect(output["total"] == 4)
        let packages = output["packages"]?.objects ?? []
        let rustls = try #require(packages.first { $0["name"] == "rustls" })
        #expect(rustls["group"] == "transitive")
        #expect(rustls["via"] == ["reqwest"])
        #expect(rustls["update"] == "unknown")
        #expect(rustls["unknown_reason"] == "latest_not_looked_up")
        let fhir = try #require(packages.first { $0["name"] == "fhir-types" })
        #expect(fhir["update"] == "within_range")
        #expect(fhir["via"] == nil)
        let thirtyfour = try #require(packages.first { $0["name"] == "thirtyfour" })
        #expect(thirtyfour["group"] == "dev")
        #expect(thirtyfour["unknown_reason"] == "no_requirement")
    }

    @Test func `The report pages through transitive crates`() async throws {
        let first = try await harness.output("get_repository_report", ["repo": "acme/api", "limit": 3])
        #expect(first["packages"]?.objects.map { $0["name"] } == ["fhir-types", "reqwest", "rustls"])
        let cursor = try #require(first["next_cursor"]?.stringValue)
        let second = try await harness.output("get_repository_report", ["repo": "acme/api", "limit": 3, "cursor": .string(cursor)])
        #expect(second["packages"]?.objects.map { $0["name"] } == ["thirtyfour"])
    }
}
