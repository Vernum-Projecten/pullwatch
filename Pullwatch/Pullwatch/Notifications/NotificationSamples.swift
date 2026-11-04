import Foundation
import PullwatchCore

/// Voorbeeldmeldingen van elke soort, gemaakt met dezelfde builder als de echte: voor de
/// voorbeelden onder Instellingen > Meldingen en het debugvenster met alle meldingen.
struct NotificationSamples {
    var builder: NotificationContentBuilder

    static let accountId = UUID(uuidString: "00000000-0000-0000-0000-00000000F00D")!
    static let repo = "octo-org/hello-world"
    private static let web = URL(string: "https://github.com/octo-org/hello-world")!

    private var pullRequest: PullRequest {
        PullRequest(
            accountId: Self.accountId, repo: Self.repo, number: 42, title: "Add a dark mode to the settings window",
            authorId: "mona", authorName: "mona", isDraft: false, createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            webURL: Self.web.appending(path: "pull/42"),
            coAuthors: [Person(name: "Hubot", login: "hubot"), Person(name: "Octocat", login: "octocat")]
        )
    }

    private var merged: PullRequest {
        PullRequest(
            accountId: Self.accountId, repo: Self.repo, number: 41, title: "Fix the crash on wake",
            authorId: "octocat", authorName: "octocat", isDraft: false, createdAt: Date(timeIntervalSince1970: 1_789_000_000),
            webURL: Self.web.appending(path: "pull/41"), state: .merged
        )
    }

    /// Een eigen PR waarvan 1 van de 8 checks mislukte.
    private var checksFailed: PullRequest {
        PullRequest(
            accountId: Self.accountId, repo: Self.repo, number: 43, title: "Speed up the start of the app",
            authorId: "mona", authorName: "mona", isDraft: false, createdAt: Date(timeIntervalSince1970: 1_790_100_000),
            webURL: Self.web.appending(path: "pull/43"), checks: .counts(CheckCounts(passed: 7, failed: 1))
        )
    }

    private var release: Tag {
        Tag(
            accountId: Self.accountId, repo: Self.repo, name: "v1.2.0", authorName: "mona",
            webURL: Self.web.appending(path: "releases/tag/v1.2.0"),
            release: ReleaseInfo(title: "Spring cleaning", authorLogin: "mona", url: Self.web.appending(path: "releases/tag/v1.2.0"))
        )
    }

    private var tag: Tag {
        Tag(accountId: Self.accountId, repo: Self.repo, name: "v1.2.1", authorName: "hubot", webURL: Self.web.appending(path: "tree/v1.2.1"))
    }

    private var vulnerability: VulnerabilityNotice {
        let v = Vulnerability(
            id: "GHSA-jf85-cpcp-j695", cve: "CVE-2019-10744", summary: "Prototype Pollution in lodash", severity: "CRITICAL",
            ecosystem: "npm", package: "lodash", version: "4.17.11", fixedIn: "4.17.12", source: "package-lock.json",
            scope: .direct
        )
        return VulnerabilityNotice(
            accountId: Self.accountId, repo: Self.repo, vulnerability: v,
            identifiers: v.sourceLine(adding: ["CVE-2019-10744"], maxAliases: 3), severityText: "CVSS 9.1",
            severityLevel: "CRITICAL", severityNote: v.severityAssessment(nil).note(for: v)
        )
    }

    private var securityAlert: SecurityAlertNotice {
        SecurityAlertNotice(
            accountId: Self.accountId, repo: Self.repo,
            alert: SecurityAlert(
                source: .codeScanning, kind: .code, number: 7, title: "Database query built from user-controlled sources",
                rule: "js/sql-injection", tool: "CodeQL", severity: "HIGH", path: "src/db.js", line: 42,
                url: Self.web.appending(path: "security/code-scanning/7")
            )
        )
    }

    private var packageUpdate: PackageSummary {
        let user = PackageUser(repoId: "\(Self.accountId.uuidString)/\(Self.repo)", repo: Self.repo, version: "18.3.1", sources: ["package.json"])
        return PackageSummary(
            id: "npm:react", label: "react", kind: "npm", latest: "19.1.0", since: nil,
            behind: [user, user, user], current: [], transitiveOnly: []
        )
    }

    var accounts: [Account] {
        [Account(id: Self.accountId, kind: .gitHub, organization: "octo-org", authMethod: .gitHubApp, login: "mona")]
    }

    /// Het voorbeeld van een soort; nil voor de soorten zonder schakelaar.
    func content(for kind: NotificationKind) -> NotificationContent? {
        var builder = builder
        builder.accounts = accounts
        return switch kind {
        case .pullRequest: builder.content(for: .pullRequest(pullRequest))
        case .merged: builder.content(for: .merged(merged))
        case .checksFailed: builder.content(for: .checksFailed(checksFailed))
        case .release: builder.content(for: .tag(release))
        case .tag: builder.content(for: .tag(tag))
        case .vulnerability: builder.vulnerability(vulnerability)
        case .securityAlert: builder.securityAlert(securityAlert)
        case .packageUpdate: builder.packageUpdates([packageUpdate])
        case .appUpdate: builder.appUpdate(AvailableUpdate(version: "2.0.0", pageURL: Self.web, downloadURL: nil, installsInApp: true))
        case .account: builder.authFailure(accounts[0])
        case .agent: builder.agentApproval(clientName: "claude-code", displayName: "Claude Code")
        }
    }

    /// Wat er boven de grens per poll komt: één melding voor 25 nieuwe PR's in één repo.
    var summary: NotificationContent {
        var builder = builder
        builder.accounts = accounts
        let prs = (1...25).map { number in
            PullRequest(
                accountId: Self.accountId, repo: Self.repo, number: number, title: "Bump dependency \(number)",
                authorId: "dependabot", authorName: "dependabot", isDraft: false, createdAt: Date(timeIntervalSince1970: 1_790_000_000),
                webURL: Self.web.appending(path: "pull/\(number)")
            )
        }
        return builder.summary(RepositoryKey(accountId: Self.accountId, repo: Self.repo), prs.map(RepositoryItem.pullRequest))
    }
}
