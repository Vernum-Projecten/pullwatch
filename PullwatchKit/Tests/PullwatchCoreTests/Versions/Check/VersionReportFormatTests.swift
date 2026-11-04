import Foundation
import Testing
@testable import PullwatchCore

/// Een rapport van een oudere check (zonder transitieve packages en bereiken) is te herkennen, zodat
/// de app opnieuw checkt en de tools het zeggen.
@Suite struct VersionReportFormatTests {
    let date = Date(timeIntervalSince1970: 1_792_000_000)

    @Test func `A report without a format is from an older check`() throws {
        let json = #"{"checkedAt": 0, "repos": []}"#
        let report = try JSONDecoder().decode(VersionReport.self, from: Data(json.utf8))
        #expect(report.format == 1)
        #expect(report.isOutdatedFormat)
    }

    @Test func `A new report has the current format and keeps it through a round trip`() throws {
        let report = VersionReport(checkedAt: date, repos: [])
        #expect(!report.isOutdatedFormat)
        let decoded = try JSONDecoder().decode(VersionReport.self, from: JSONEncoder().encode(report))
        #expect(decoded.format == VersionReport.currentFormat)
    }

    @Test func `Refreshing one repository of an older report keeps it older`() {
        let old = VersionReport(checkedAt: date, repos: [], format: 1)
        let repo = RepoVersions(accountId: UUID(), repo: "acme/web", components: [])
        #expect(old.replacing(repo).isOutdatedFormat)
        #expect(old.visible(disabled: [.osv], accountKinds: [:]).isOutdatedFormat)
    }

    @Test func `A package only pulled in transitively shows in the overview when it is vulnerable`() {
        let rustls = PackageUse(ecosystem: "crates.io", name: "rustls", installs: [
            PackageInstall(version: "0.23.44", workspace: "e2e", scope: .transitive, via: ["thirtyfour", "reqwest"], source: "e2e/Cargo.lock"),
        ])
        let quiet = PackageUse(ecosystem: "crates.io", name: "itoa", installs: [
            PackageInstall(version: "1.0.11", workspace: "", scope: .transitive, via: ["serde_json"], source: "Cargo.lock"),
        ])
        let vulnerability = Vulnerability(
            id: "GHSA-2mjx-qc3c-rqvc", cve: nil, summary: "rustls bug", severity: "HIGH", ecosystem: "crates.io", package: "rustls",
            version: "0.23.44", fixedIn: "0.23.45", source: "e2e/Cargo.lock", workspace: "e2e", scope: .transitive, via: ["thirtyfour", "reqwest"]
        )
        let repo = RepoVersions(
            accountId: UUID(), repo: "acme/forms", components: [], vulnerabilities: [vulnerability], otherPackages: [rustls, quiet]
        )
        let summaries = VersionReport(checkedAt: date, repos: [repo]).packageSummaries()
        #expect(summaries.map(\.label) == ["rustls"])
        let summary = summaries.first
        #expect(summary?.isTransitiveOnly == true)
        #expect(summary?.transitiveOnly.first?.installs.first?.via == ["thirtyfour", "reqwest"])
    }
}
