import Foundation
import PullwatchCore
import Testing

@testable import Pullwatch

/// Wat elke melding zegt en doet, zonder er een te versturen: tekst in het Engels en het
/// Nederlands, groep per repo, knoppen, belang, plaatje en wat een klik nodig heeft.
@MainActor @Suite struct NotificationContentTests {
    private let accountId = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
    private let repo = "octo-org/hello-world"
    private let web = URL(string: "https://github.com/octo-org/hello-world")!

    private func language(_ code: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: code, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    private func builder(_ code: String = "en", kind: ProviderKind = .gitHub, quiet: Bool = false) throws -> NotificationContentBuilder {
        NotificationContentBuilder(
            accounts: [Account(id: accountId, kind: kind, organization: "octo-org", authMethod: .pat)],
            quiet: quiet, bundle: try language(code)
        )
    }

    private func pr(_ number: Int = 42, title: String = "Add dark mode", author: String = "mona", coAuthors: [String] = [], draft: Bool = false) -> PullRequest {
        PullRequest(
            accountId: accountId, repo: repo, number: number, title: title, authorId: author, authorName: author,
            isDraft: draft, createdAt: Date(timeIntervalSince1970: 1_790_000_000), webURL: web.appending(path: "pull/\(number)"),
            coAuthors: coAuthors.map { Person(name: $0, login: $0) }
        )
    }

    private func tag(_ name: String = "v1.2.0", release: ReleaseInfo? = nil) -> PullwatchCore.Tag {
        PullwatchCore.Tag(accountId: accountId, repo: repo, name: name, authorName: "hubot", webURL: web.appending(path: "tree/\(name)"), release: release)
    }

    // MARK: PR's

    @Test func aNewPullRequestReadsAtAGlance() throws {
        let content = try builder().content(for: .pullRequest(pr(coAuthors: ["hubot", "octocat"])))
        #expect(content.title == "New Pull Request")
        #expect(content.subtitle == "\(repo) #42")
        #expect(content.body == "Add dark mode\nby mona and 2 others")
        #expect(!content.title.contains(":"))
        #expect(content.identifier == pr().dedupKey)
        #expect(content.threadIdentifier == "\(accountId.uuidString)/\(repo)")
        #expect(content.category == .item)
        #expect(content.importance == .of(.pullRequest))
        #expect(content.importance.level == .active)
        #expect(content.avatarURL == URL(string: "https://github.com/mona.png?size=64"))
        #expect(content.payload.url == web.appending(path: "pull/42"))
        #expect(content.payload.historyKeys == [pr().dedupKey])
        #expect(content.payload.watchKinds == [.pullRequests])
        #expect(content.payload.accountId == accountId)
        #expect(content.payload.repo == repo)
    }

    @Test(arguments: [ProviderKind.gitHub, .gitLab, .azureDevOps], ["new", "merged", "checks failed"])
    func `The subtitle names the repository and the number as the service writes it`(kind: ProviderKind, event: String) throws {
        let item: RepositoryItem = switch event {
        case "merged": .merged(pr())
        case "checks failed": .checksFailed(pr())
        default: .pullRequest(pr())
        }

        let content = try builder(kind: kind).content(for: item)

        #expect(content.subtitle == "\(repo) \(kind == .gitHub ? "#" : "!")42")
    }

    @Test func `A tag keeps the repository alone as its subtitle`() throws {
        #expect(try builder().content(for: .tag(tag())).subtitle == repo)
    }

    @Test func `Without its account the subtitle is the repository alone`() throws {
        let builder = NotificationContentBuilder(accounts: [], bundle: try language("en"))

        #expect(builder.content(for: .pullRequest(pr())).subtitle == repo)
    }

    @Test func coAuthorsAreNamedOrCounted() throws {
        let builder = try builder()
        #expect(builder.byline("mona", others: []) == "by mona")
        #expect(builder.byline("mona", others: ["hubot"]) == "by mona and hubot")
        #expect(builder.byline("mona", others: ["hubot", "octocat"]) == "by mona and 2 others")
        #expect(builder.byline("mona", others: ["Mona"]) == "by mona", "de auteur telt niet als co-auteur")
        #expect(builder.byline(nil, others: ["hubot"]) == nil)
        #expect(builder.byline("  ", others: []) == nil)
    }

    @Test func dutchTextComesFromTheCatalog() throws {
        let content = try builder("nl").content(for: .pullRequest(pr(coAuthors: ["hubot", "octocat"])))
        #expect(content.title == "Nieuwe pull request")
        #expect(content.body == "Add dark mode\ndoor mona en 2 anderen")
        #expect(try builder("nl").byline("mona", others: ["hubot"]) == "door mona en hubot")
    }

    @Test func draftsAndGitLabSayWhatTheyAre() throws {
        #expect(try builder().content(for: .pullRequest(pr(draft: true))).title == "New Draft Pull Request")
        #expect(try builder(kind: .gitLab).content(for: .pullRequest(pr())).title == "New Merge Request")
        #expect(try builder(kind: .gitLab).content(for: .pullRequest(pr(draft: true))).title == "New Draft Merge Request")
        // Zonder GitHub geen profielfoto: dan het teken van de soort.
        #expect(try builder(kind: .gitLab).content(for: .pullRequest(pr())).avatarURL == nil)
    }

    @Test func `The avatar of a pull request is the one the API gave, also for a bot`() throws {
        let avatar = URL(string: "https://avatars.githubusercontent.com/in/15368?v=4")
        var bot = pr(author: "github-actions[bot]")
        bot.authorAvatarURL = avatar
        #expect(try builder().content(for: .pullRequest(bot)).avatarURL == avatar)
        #expect(try builder().content(for: .merged(bot)).avatarURL == avatar)
        // Zonder foto van de API geen gok: `github.com/github-actions[bot].png` bestaat niet.
        #expect(try builder().content(for: .pullRequest(pr(author: "github-actions[bot]"))).avatarURL == nil)
        // Een foto van GitLab zelf telt ook.
        var gitLab = pr()
        gitLab.authorAvatarURL = URL(string: "https://gitlab.com/uploads/-/system/user/avatar/5/avatar.png")
        #expect(try builder(kind: .gitLab).content(for: .pullRequest(gitLab)).avatarURL == gitLab.authorAvatarURL)
    }

    @Test func mergedIsQuietAndHasItsOwnIdentifier() throws {
        let merged = try builder().content(for: .merged(pr()))
        #expect(merged.title == "Pull Request Merged")
        #expect(merged.identifier == pr().dedupKey + ":completed")
        #expect(merged.payload.historyKeys == [pr().dedupKey])
        #expect(merged.payload.watchKinds == [.merged])
        #expect(merged.importance.level == .passive)
        #expect(!merged.importance.playsSound)
        #expect(try builder(kind: .azureDevOps).content(for: .merged(pr())).title == "Pull Request Completed")
        #expect(try builder(kind: .gitLab).content(for: .merged(pr())).title == "Merge Request Merged")
    }

    @Test func `Failed checks say how many of the checks failed`() throws {
        var own = pr()
        own.checks = .counts(CheckCounts(passed: 7, failed: 1))
        let content = try builder().content(for: .checksFailed(own))
        #expect(content.title == "Checks Failed")
        #expect(content.body == "Add dark mode\n1 of 8 checks failed")
        #expect(content.identifier == own.dedupKey + ":checks")
        #expect(content.payload.url == own.webURL)
        #expect(content.payload.historyKeys == [own.dedupKey])
        #expect(content.importance.level == .active)
        #expect(try builder("nl").content(for: .checksFailed(own)).body == "Add dark mode\n1 van 8 checks mislukt")
        let summary = try builder().summary(RepositoryKey(accountId: accountId, repo: repo), [.checksFailed(own), .checksFailed(pr(7))])
        #expect(summary.title == "Checks Failed on 2 Pull Requests")
    }

    // MARK: Releases en tags

    @Test func aReleaseIsNamedAfterItsTagWithItsTitleInTheBody() throws {
        let info = ReleaseInfo(title: "Spring cleaning", authorLogin: "mona", authorAvatarURL: URL(string: "https://avatars.example/mona"), url: web)
        let content = try builder().content(for: .tag(tag(release: info)))
        #expect(content.title == "New Release v1.2.0")
        #expect(content.body == "Spring cleaning\nby mona")
        #expect(content.kind == .release)
        #expect(content.importance.level == .active)
        #expect(content.avatarURL == URL(string: "https://avatars.example/mona"))
        #expect(content.payload.watchKinds == [.tags])

        var pre = info
        pre.isPrerelease = true
        #expect(try builder().content(for: .tag(tag("v2.0.0-beta.1", release: pre))).title == "New Pre-release v2.0.0-beta.1")
    }

    @Test func aTagWithoutAReleaseIsPassive() throws {
        let content = try builder().content(for: .tag(tag()))
        #expect(content.title == "New Tag v1.2.0")
        #expect(content.body == "by hubot")
        #expect(content.kind == .tag)
        #expect(content.importance.level == .passive)
        #expect(content.identifier == tag().dedupKey)
    }

    // MARK: Samenvatting boven de grens

    @Test func aboveTheCapOneSummaryPerRepository() throws {
        let prs = (1...25).map { pr($0, title: "Bump \($0)") }
        let key = RepositoryKey(accountId: accountId, repo: repo)
        let content = try builder().summary(key, prs.map(RepositoryItem.pullRequest))
        #expect(content.title == "25 New Pull Requests")
        #expect(content.subtitle == repo)
        #expect(content.body == "Bump 1\nBump 2\nBump 3\nand 22 more")
        #expect(content.threadIdentifier == key.threadIdentifier)
        #expect(content.category == .summary)
        #expect(content.payload.historyKeys.count == 25)
        #expect(content.payload.url == nil, "een klik opent de repopagina")
        #expect(content.payload.watchKinds == [.pullRequests])

        let mixed = try builder().summary(key, [.pullRequest(pr()), .tag(tag()), .merged(pr(7))])
        #expect(mixed.title == "3 Updates")
        #expect(mixed.payload.watchKinds == [.pullRequests, .tags, .merged])
        #expect(mixed.importance == .of(.pullRequest), "zo belangrijk als het belangrijkste item")
        #expect(try builder("nl").summary(key, [.tag(tag()), .tag(tag("v2"))]).title == "2 nieuwe tags")
    }

    // MARK: Kwetsbaarheden en beveiligingsmeldingen

    private var lodash: Vulnerability {
        Vulnerability(
            id: "GHSA-jf85-cpcp-j695", cve: "CVE-2019-10744", summary: "Prototype Pollution in lodash", severity: "CRITICAL",
            ecosystem: "npm", package: "lodash", version: "4.17.11", fixedIn: "4.17.12", source: "package-lock.json"
        )
    }

    @Test func aVulnerabilityLeadsWithItsSeverityAndCarriesTheSourceText() throws {
        let notice = VulnerabilityNotice(
            accountId: accountId, repo: repo, vulnerability: lodash,
            identifiers: "GHSA-jf85-cpcp-j695 (GitHub), also CVE-2019-10744", severityText: "Critical, CVSS 9.1",
            severityLevel: "CRITICAL", severityNote: "Severity from CVSS 3.1 of GitHub", provenance: "Direct", fixText: "Within range"
        )
        let content = try builder().vulnerability(notice)
        #expect(content.title == "Critical Vulnerability")
        #expect(content.subtitle == repo)
        #expect(content.body == [
            "Prototype Pollution in lodash",
            "lodash 4.17.11, fixed in 4.17.12",
            "GHSA-jf85-cpcp-j695 (GitHub), also CVE-2019-10744 [Critical, CVSS 9.1]",
            "Severity from CVSS 3.1 of GitHub",
            "Direct",
            "Within range",
        ].joined(separator: "\n"))
        #expect(content.category == .vulnerability)
        #expect(content.importance.level == .active)
        #expect(content.importance.relevance > NotificationImportance.of(.pullRequest).relevance)
        #expect(content.payload.url == lodash.pageURL, "een klik opent het advies bij zijn eigen database")
        #expect(content.payload.package == "lodash")
        #expect(content.payload.advisoryId == "GHSA-jf85-cpcp-j695")
        #expect(content.threadIdentifier == "\(accountId.uuidString)/\(repo)")
        #expect(content.identifier == "cve-\(accountId.uuidString)/\(repo)-GHSA-jf85-cpcp-j695-lodash")
    }

    @Test func severityTitlesFollowTheBestSource() throws {
        func title(_ level: String?) throws -> String {
            try builder().vulnerability(VulnerabilityNotice(accountId: accountId, repo: repo, vulnerability: lodash, severityLevel: level)).title
        }
        #expect(try title("HIGH") == "High-Severity Vulnerability")
        #expect(try title("MODERATE") == "Moderate Vulnerability")
        #expect(try title("LOW") == "Low-Severity Vulnerability")
        // Zonder eigen beoordeling telt de ernst van OSV.
        #expect(try title(nil) == "Critical Vulnerability")
        let noFix = Vulnerability(id: "RUSTSEC-2026-0001", cve: nil, summary: nil, severity: nil, ecosystem: "crates.io",
                                  package: "tokio", version: "1.0.0", fixedIn: nil, source: "Cargo.lock")
        let content = try builder().vulnerability(VulnerabilityNotice(accountId: accountId, repo: repo, vulnerability: noFix))
        #expect(content.title == "New Vulnerability")
        #expect(content.body == "tokio 1.0.0, not fixed yet")
    }

    @Test func manyVulnerabilitiesInOneRepositoryBecomeOneNotification() throws {
        let notices = (1...4).map { number in
            VulnerabilityNotice(
                accountId: accountId, repo: repo,
                vulnerability: Vulnerability(id: "GHSA-\(number)", cve: nil, summary: nil, severity: "HIGH", ecosystem: "npm",
                                             package: "pkg\(number)", version: "1.0.\(number)", fixedIn: nil, source: "package.json")
            )
        }
        let content = try builder().vulnerabilities(RepositoryKey(accountId: accountId, repo: repo), notices)
        #expect(content.title == "4 new vulnerabilities")
        #expect(content.body == "pkg1 1.0.1\npkg2 1.0.2\npkg3 1.0.3\nand 1 more")
        #expect(content.category == .finding)
        #expect(content.payload.url == nil)
        #expect(content.payload.repo == repo)
    }

    @Test func aSecurityAlertNamesWhereItIs() throws {
        let alert = SecurityAlert(
            source: .codeScanning, kind: .code, number: 7, title: "SQL built from user input", rule: "js/sql-injection",
            tool: "CodeQL", severity: "HIGH", path: "src/db.js", line: 42, url: web.appending(path: "security/code-scanning/7")
        )
        let content = try builder().securityAlert(SecurityAlertNotice(accountId: accountId, repo: repo, alert: alert))
        #expect(content.title == "High-Severity Security Alert")
        #expect(content.body == "SQL built from user input\nsrc/db.js:42\njs/sql-injection (CodeQL)")
        #expect(content.payload.url == alert.url)
        #expect(content.category == .finding)
        #expect(content.importance.level == .active)
    }

    // MARK: Versies, update, account, stille uren

    @Test func newVersionsArePassiveAndOpenDependencies() throws {
        let user = PackageUser(repoId: "\(accountId.uuidString)/\(repo)", repo: repo, version: "18.3.1", sources: ["package.json"])
        let react = PackageSummary(id: "npm:react", label: "react", kind: "npm", latest: "19.1.0", since: nil,
                                   behind: [user, user], current: [], transitiveOnly: [])
        let one = try #require(try builder().packageUpdates([react]))
        #expect(one.title == "react 19.1.0 available")
        #expect(one.importance.level == .passive)
        #expect(one.payload.section == "versions")
        #expect(one.payload.package == "react")
        #expect(one.threadIdentifier == "versions")
        let many = try #require(try builder().packageUpdates([react, react, react, react]))
        #expect(many.title == "4 new versions")
        #expect(many.body.hasSuffix("and 1 more"))
        #expect(many.payload.package == nil)
        #expect(try builder().packageUpdates([]) == nil)
    }

    @Test func appUpdateAndAccountProblems() throws {
        let page = URL(string: "https://github.com/alessandro823/pullwatch/releases")!
        let inApp = try builder().appUpdate(AvailableUpdate(version: "2.0.0", pageURL: page, downloadURL: nil, installsInApp: true))
        #expect(inApp.title == "Pullwatch 2.0.0 is available")
        #expect(inApp.payload.installsUpdate)
        #expect(inApp.identifier == "update-2.0.0")
        let download = try builder().appUpdate(AvailableUpdate(version: "2.0.0", pageURL: page, downloadURL: nil))
        #expect(download.payload.url == page)

        let account = Account(id: accountId, kind: .gitHub, organization: "octo-org", authMethod: .pat)
        let failure = try builder().authFailure(account)
        #expect(failure.title == account.displayName)
        #expect(!failure.title.hasPrefix("Pullwatch:"))
        #expect(failure.payload.section == "settings")
        #expect(failure.identifier == "auth-\(accountId.uuidString)")
    }

    @Test func quietHoursMakeEveryKindSilent() throws {
        let quiet = try builder(quiet: true)
        let all = [
            quiet.content(for: .pullRequest(pr())),
            quiet.content(for: .tag(tag(release: ReleaseInfo(title: nil, url: web)))),
            quiet.vulnerability(VulnerabilityNotice(accountId: accountId, repo: repo, vulnerability: lodash)),
        ]
        for content in all {
            #expect(content.importance.level == .passive)
            #expect(!content.importance.playsSound)
        }
    }

    // MARK: Knoppen en userInfo

    @Test func categoriesHaveAtMostFourActionsAndNoOpenButton() {
        for category in NotificationCategory.allCases {
            #expect(!category.actions.isEmpty)
            #expect(category.actions.count <= 4)
            #expect(NotificationCategory(identifier: category.identifier) == category)
        }
        #expect(NotificationCategory.item.actions == [.markRead, .openRepository, .mute])
        #expect(NotificationCategory.vulnerability.actions == [.showInPullwatch, .copyAdvisoryId, .openRepository])
        let identifiers = NotificationAction.allCases.map(\.identifier)
        #expect(Set(identifiers).count == identifiers.count, "elke knop een eigen id")
        for action in NotificationAction.allCases {
            #expect(NotificationAction(identifier: action.identifier) == action)
            #expect(!action.title.isEmpty)
        }
        #expect(NotificationAction.openRepository.opensWindow)
        #expect(!NotificationAction.markRead.opensWindow)
        #expect(!NotificationAction.mute.opensWindow)
    }

    @Test func payloadRoundTripsThroughUserInfo() {
        let payload = NotificationPayload(
            url: web, historyKeys: ["a", "b"], section: "versions", installsUpdate: true, accountId: accountId,
            repo: repo, watchKinds: [.pullRequests, .tags], package: "lodash", advisoryId: "CVE-1"
        )
        let info = payload.userInfo.reduce(into: [AnyHashable: Any]()) { $0[$1.key] = $1.value }
        #expect(NotificationPayload(userInfo: info) == payload)
    }

    @Test func oldNotificationsStillOpen() {
        // Zoals een eerdere Pullwatch ze verstuurde.
        let old = NotificationPayload(userInfo: ["url": web.absoluteString, "key": "k1"])
        #expect(old.url == web)
        #expect(old.historyKeys == ["k1"])
        #expect(NotificationPayload(userInfo: ["action": "install-update"]).installsUpdate)
        #expect(NotificationPayload(userInfo: [:]) == NotificationPayload())
        #expect(NotificationPayload(historyKeys: ["only"]).userInfo["key"] as? String == "only")
    }

    @Test func everySwitchableKindHasAPreview() {
        let samples = NotificationSamples(builder: NotificationContentBuilder())
        for kind in NotificationKind.allCases {
            let content = samples.content(for: kind)
            #expect(content?.kind == kind)
            #expect(content?.title.isEmpty == false)
        }
        #expect(samples.summary.category == .summary)
    }
}
