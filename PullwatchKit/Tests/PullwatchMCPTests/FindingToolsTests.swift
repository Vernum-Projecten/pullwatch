import Foundation
import MCP
import PullwatchCore
import PullwatchMCP
import Testing

/// `list_vulnerabilities` en `explain_update` over de fixtures.
@Suite struct FindingToolsTests {
    let harness = ToolHarness()

    // MARK: - list_vulnerabilities

    @Test func `Lists package vulnerabilities and security alerts, worst first, with their source and fix`() async throws {
        let output = try await harness.output("list_vulnerabilities")

        let findings = output["findings"]?.objects ?? []
        #expect(findings.count == 2)
        let alert = try #require(findings.first)
        #expect(alert["kind"] == "security_alert")
        #expect(alert["found_by"] == "GitHub code scanning")
        #expect(alert["severity"] == "critical")
        #expect(alert["rule"] == "js/sql-injection")
        #expect(alert["path"] == "src/db.js")
        #expect(alert["line"] == 12)
        let vulnerability = try #require(findings.last)
        #expect(vulnerability["kind"] == "package_vulnerability")
        #expect(vulnerability["found_by"] == "OSV.dev")
        #expect(vulnerability["id"] == "GHSA-qwcr-r2fm-qrc7")
        #expect(vulnerability["identifiers"] == ["GHSA-qwcr-r2fm-qrc7", "CVE-2024-45590"])
        #expect(vulnerability["database"] == "GitHub")
        #expect(vulnerability["severity"] == "high")
        #expect(vulnerability["package"] == "body-parser")
        #expect(vulnerability["fixed_in"] == "1.20.3")
        #expect(vulnerability["origin"] == "transitive")
        #expect(vulnerability["fixes"] == ["Update express so it pulls in body-parser 1.20.3 or newer."])
        #expect(output["not_checked"] == [])
        #expect(output["unchecked_repositories"] == [])
    }

    @Test(arguments: [("critical", 1), ("high", 2), ("low", 2)])
    func `min_severity drops the milder findings`(minimum: String, count: Int) async throws {
        let output = try await harness.output("list_vulnerabilities", ["min_severity": .string(minimum)])

        #expect(output["findings"]?.arrayValue?.count == count)
    }

    @Test func `Findings of a repository that is not followed never appear`() async throws {
        let wire = try await harness.wire("list_vulnerabilities", ["limit": 100])
        #expect(!wire.contains("GHSA-hidden"))

        let message = try await harness.error("list_vulnerabilities", ["repo": "acme/old"])
        #expect(message.hasPrefix("Repository acme/old is not followed in Pullwatch."))
    }

    @Test func `With OSV off a repository is not checked, never free of vulnerabilities`() async throws {
        var harness = harness
        harness.source.disabled = [.osv]

        let output = try await harness.output("list_vulnerabilities", ["repo": "acme/web"])

        #expect(output["findings"]?.objects.compactMap { $0["kind"]?.stringValue } == ["security_alert"])
        #expect(output["not_checked"] == [["source": "osv", "message": "Not checked: source OSV.dev is off.", "repository": "acme/web"]])
        let result = try await harness.call("list_vulnerabilities", ["repo": "acme/web"])
        #expect(ToolHarness.texts(result).first?.contains("Not everything was checked") == true)
    }

    @Test func `With GitHub security off its alerts are not checked`() async throws {
        var harness = harness
        harness.source.disabled = [.gitHubSecurity]

        let output = try await harness.output("list_vulnerabilities", ["repo": "acme/web"])

        #expect(output["findings"]?.objects.compactMap { $0["kind"]?.stringValue } == ["package_vulnerability"])
        #expect(output["not_checked"] == [["source": "gitHubSecurity", "message": "Not checked: source GitHub security is off.", "repository": "acme/web"]])
    }

    @Test func `With the advisory database off the missing details are named`() async throws {
        var harness = harness
        harness.source.disabled = [.gitHubAdvisoryDatabase]

        let output = try await harness.output("list_vulnerabilities", ["repo": "acme/web"])

        #expect(output["not_checked"] == [[
            "source": "gitHubAdvisoryDatabase", "repository": "acme/web",
            "message": "Not checked: source GitHub Advisory Database is off (no severity, CVSS or CWE details from GitHub).",
        ]])
    }

    @Test func `A followed repository without a check is listed as unchecked`() async throws {
        var harness = harness
        harness.source.accountList[0].repoWatch["acme/new"] = .prs

        let output = try await harness.output("list_vulnerabilities", ["repo": "acme/new"])

        #expect(output["findings"] == [])
        #expect(output["unchecked_repositories"] == [["repository": "acme/new", "reason": "Pullwatch has not checked this repository yet."]])
    }

    @Test func `Findings are paged`() async throws {
        let output = try await harness.output("list_vulnerabilities", ["limit": 1, "cursor": "1"])

        #expect(output["findings"]?.objects.compactMap { $0["kind"]?.stringValue } == ["package_vulnerability"])
        #expect(output["total"] == 2)
        #expect(output["next_cursor"] == nil)
    }

    // MARK: - explain_update

    @Test func `Explains a package that needs a new major version`() async throws {
        let output = try await harness.output("explain_update", ["repo": "acme/web", "package": "Express"])

        #expect(output["package"] == "express")
        #expect(output["ecosystem"] == "npm")
        #expect(output["latest"] == "5.1.0")
        let install = try #require(output["installs"]?.objects.first)
        #expect(install["update"] == "needs_manifest_change")
        #expect(install["step"] == "major")
        #expect(install["requested"] == "^4.19.0")
        #expect(install["explanation"] == "express 5.1.0 needs a new major version (outside ^4.19.0).")
        #expect(output["vulnerabilities"] == [])
    }

    @Test func `Explains a transitive package with its vulnerability fix`() async throws {
        let output = try await harness.output("explain_update", ["repo": "acme/web", "package": "body-parser"])

        let install = try #require(output["installs"]?.objects.first)
        #expect(install["scope"] == "transitive")
        #expect(install["via"] == ["express"])
        #expect(output["vulnerabilities"] == [[
            "id": "GHSA-qwcr-r2fm-qrc7", "severity": "high", "fixed_in": "1.20.3",
            "fix": "Update express so it pulls in body-parser 1.20.3 or newer.",
        ]])
    }

    @Test func `A package whose registry is off is not checked`() async throws {
        let output = try await harness.output("explain_update", ["repo": "group/app", "package": "requests"])

        #expect(output["latest"] == nil)
        #expect(output["installs"]?.objects.first?["update"] == "not_checked")
        #expect(output["not_checked"] == [["source": "pyPI", "message": "Not checked: source PyPI is off.", "repository": "group/app"]])
        let result = try await harness.call("explain_update", ["repo": "group/app", "package": "requests"])
        #expect(ToolHarness.texts(result).first == "requests in group/app: Not checked: source PyPI is off.")
    }

    @Test func `A package the repository does not use is a tool error`() async throws {
        let message = try await harness.error("explain_update", ["repo": "acme/web", "package": "react"])

        #expect(message == "acme/web does not use a package named react in Pullwatch's last check. get_repository_report lists its packages.")
    }

    @Test(arguments: ["acme/old", "evil/other"])
    func `Explaining an update in a repository that is not followed is a tool error`(repo: String) async throws {
        let message = try await harness.error("explain_update", ["repo": .string(repo), "package": "hidden"])

        #expect(message == "Repository \(repo) is not followed in Pullwatch. list_repositories lists the repositories you can ask about.")
    }
}
