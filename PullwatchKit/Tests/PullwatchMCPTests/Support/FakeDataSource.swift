import Foundation
import PullwatchCore
import PullwatchMCP

/// Een `MCPDataSource` in het geheugen, met fixtures die elke regel van de tools raken: PR's in
/// elke stand (draft, in de rij, gemerged, gesloten) met en zonder checks, tags met en zonder
/// release, repo's met kwetsbaarheden en meldingen, een repo die niet meer gevolgd wordt, een bron
/// die uit staat en accounts met een token in velden die nooit naar buiten mogen. Het overzicht
/// en het getoonde rapport rekent hij uit zoals de app (`RepoOverview`, `VersionReport.visible`).
struct FakeDataSource: MCPDataSource {
    /// Staat in elk veld van een account dat geen tool mag tonen; geen enkele uitvoer mag het bevatten.
    static let secret = "fake-token-never-shared-7f3a9c"

    static let gitHubId = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    static let gitLabId = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    static let checkedAt = ISO8601DateFormatter().date(from: "2026-11-03T10:00:00Z")!
    static let now = ISO8601DateFormatter().date(from: "2026-11-04T09:00:00Z")!

    var accountList: [Account]
    var disabled: Set<DataSourceID> = [.pyPI]
    var history: History
    var report: VersionReport?
    var userIds: [UUID: String] = [gitHubId: "1001"]
    var states: [UUID: AccountState] = [
        gitHubId: .ok(lastPoll: now),
        gitLabId: .failed(.unauthorized, since: checkedAt),
    ]
    var lastPoll: Date? = now
    var sync: SyncStatus = .idle

    init() {
        accountList = Self.accounts
        history = Self.history
        report = Self.report
    }

    // MARK: - MCPDataSource

    func accounts() async -> [Account] { accountList }
    func disabledSources() async -> Set<DataSourceID> { disabled }
    func historyItems() async -> [HistoryItem] { history.items }
    func currentUserIds() async -> [UUID: String] { userIds }

    func repoSummaries() async -> [RepoSummary] {
        RepoOverview.summaries(accounts: accountList, report: await versionReport(), history: history)
    }

    func versionReport() async -> VersionReport? {
        let kinds = Dictionary(accountList.map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
        return report?.visible(disabled: disabled, accountKinds: kinds)
    }

    func updateContext(for repo: RepoVersions) async -> UpdateContext {
        UpdateContext(repo: repo, metadata: report?.packageMetadata ?? [:])
    }

    func activityStats(period: StatsPeriod, filter: ActivityFilter) async -> ActivityStats {
        var cache = ActivityStatsCache()
        return cache.stats(history: history, period: period, filter: filter, now: Self.now)
    }

    func accountStates() async -> [UUID: AccountState] { states }
    func lastSuccessfulPoll() async -> Date? { lastPoll }
    func syncStatus() async -> SyncStatus { sync }

    // MARK: - Accounts

    /// GitHub (ingelogd met de app, volgt acme/web en acme/api, niet meer acme/old) en een eigen
    /// GitLab-server. Het token staat in de gebruiker van de CLI en in de URL van de server.
    static let accounts: [Account] = [
        Account(
            id: gitHubId, kind: .gitHub, organization: "acme", authMethod: .gitHubApp, login: "octo",
            repoWatch: ["acme/web": WatchSet(prs: true, tags: true), "acme/api": .prs, "acme/old": .none],
            cliUser: secret
        ),
        Account(
            id: gitLabId, kind: .gitLab, organization: "group", authMethod: .pat,
            repoWatch: ["group/app": .prs],
            instanceURL: URL(string: "https://oauth2:\(secret)@gitlab.example.com")
        ),
    ]

    // MARK: - Geschiedenis

    static func pr(
        _ number: Int, repo: String = "acme/web", account: UUID = gitHubId, title: String? = nil, author: String = "octo",
        authorId: String = "1001", draft: Bool = false, state: PRState = .open, checks: PRChecks? = nil,
        queue: MergeQueueEntry? = nil, created: Int
    ) -> PullRequest {
        PullRequest(
            accountId: account, repo: repo, number: number, title: title ?? "Change \(number)", authorId: authorId, authorName: author,
            isDraft: draft, createdAt: checkedAt.addingTimeInterval(TimeInterval(created) * 3600),
            webURL: URL(string: "https://github.com/\(repo)/pull/\(number)")!, state: state,
            closedAt: state == .open ? nil : checkedAt.addingTimeInterval(TimeInterval(created + 1) * 3600),
            coAuthors: number == 1 ? [Person(name: "Ada", login: "ada", email: "ada@example.com")] : [],
            checks: checks, mergeQueue: queue
        )
    }

    static let pullRequests: [PullRequest] = [
        pr(1, title: "Add login", checks: .counts(CheckCounts(passed: 3, failed: 1)), created: 10),
        pr(2, title: "Draft work", author: "ada", authorId: "2002", draft: true, created: 9),
        pr(3, title: "Ready to merge", author: "ada", authorId: "2002", checks: .counts(CheckCounts(passed: 4)),
           queue: MergeQueueEntry(kind: .mergeQueue, position: 1, enqueuedAt: checkedAt), created: 8),
        pr(4, title: "Merged fix", state: .merged, checks: .counts(CheckCounts(passed: 2, skipped: 1)), created: 7),
        pr(5, title: "Closed idea", author: "bob", authorId: "3003", state: .closed, created: 6),
        pr(6, title: "Still running", author: "bob", authorId: "3003", checks: .counts(CheckCounts(passed: 1, pending: 2)), created: 5),
        pr(7, title: "No permission", author: "bob", authorId: "3003", checks: .needsPermission, created: 4),
        pr(10, repo: "group/app", account: gitLabId, title: "GitLab change", author: "gina", authorId: "77", created: 3),
        // Niet meer gevolgd: bestaat niet voor de agent.
        pr(99, repo: "acme/old", title: "Hidden change", created: 11),
    ]

    static let tags: [Tag] = [
        Tag(accountId: gitHubId, repo: "acme/web", name: "v1.2.0", authorName: "octo", webURL: URL(string: "https://github.com/acme/web/releases/tag/v1.2.0")!,
            createdAt: checkedAt.addingTimeInterval(2 * 3600),
            release: ReleaseInfo(title: "Spring release", isPrerelease: false, publishedAt: checkedAt.addingTimeInterval(2 * 3600),
                                 url: URL(string: "https://github.com/acme/web/releases/tag/v1.2.0")!)),
        Tag(accountId: gitHubId, repo: "acme/web", name: "v1.1.0", authorName: "ada", webURL: URL(string: "https://github.com/acme/web/tree/v1.1.0")!,
            createdAt: checkedAt.addingTimeInterval(-24 * 3600)),
        Tag(accountId: gitHubId, repo: "acme/old", name: "v0.9.0", authorName: "octo", webURL: URL(string: "https://github.com/acme/old/tree/v0.9.0")!,
            createdAt: checkedAt),
    ]

    /// PR's 4, 5 en de oude tag zijn gelezen; de rest niet.
    static var history: History {
        var history = History()
        // De oudere tags eerder gezien, zodat v1.2.0 de nieuwste tag van acme/web is.
        history.add(pullRequests: [], tags: Array(tags.dropFirst()), at: checkedAt.addingTimeInterval(-24 * 3600))
        history.add(pullRequests: pullRequests, tags: [tags[0]], at: checkedAt)
        for pr in pullRequests where pr.number == 4 || pr.number == 5 { history.markRead(pr.dedupKey) }
        if let old = tags.last { history.markRead(old.dedupKey) }
        return history
    }

    // MARK: - Versierapport

    static let bodyParserVulnerability = Vulnerability(
        id: "GHSA-qwcr-r2fm-qrc7", cve: "CVE-2024-45590", summary: "body-parser vulnerable to denial of service", severity: "HIGH",
        ecosystem: "npm", package: "body-parser", version: "1.20.2", fixedIn: "1.20.3", source: "package-lock.json",
        workspace: "", scope: .transitive, via: ["express"], requested: "1.20.2"
    )

    static let report = VersionReport(
        checkedAt: checkedAt,
        repos: [
            RepoVersions(
                accountId: gitHubId, repo: "acme/web",
                components: [ComponentVersion(product: "nodejs", label: "Node.js", version: "18", latest: "22", status: .eol, sources: [".nvmrc"])],
                vulnerabilities: [bodyParserVulnerability],
                packages: [
                    PackageUse(ecosystem: "npm", name: "express", installs: [
                        PackageInstall(version: "4.19.2", workspace: "", scope: .direct, source: "package.json", requested: "^4.19.0"),
                    ]),
                    PackageUse(ecosystem: "npm", name: "left-pad", installs: [
                        PackageInstall(version: "1.3.0", workspace: "", scope: .direct, source: "package.json", requested: "^1.3.0"),
                    ]),
                ],
                otherPackages: [
                    PackageUse(ecosystem: "npm", name: "body-parser", installs: [
                        PackageInstall(version: "1.20.2", workspace: "", scope: .transitive, via: ["express"], source: "package-lock.json", requested: "1.20.2"),
                    ]),
                ],
                security: SecurityScan(
                    feeds: [
                        SecurityFeed(kind: .codeScanning, availability: .available),
                        SecurityFeed(kind: .secretScanning, availability: .available, link: URL(string: "https://github.com/acme/web/security/secret-scanning")),
                    ],
                    alerts: [SecurityAlert(
                        source: .codeScanning, kind: .code, number: 7, title: "Database query built from user-controlled sources",
                        rule: "js/sql-injection", tool: "CodeQL", severity: "CRITICAL", path: "src/db.js", line: 12,
                        url: URL(string: "https://github.com/acme/web/security/code-scanning/7")!, createdAt: checkedAt
                    )],
                    secretCount: 2
                )
            ),
            RepoVersions(
                accountId: gitHubId, repo: "acme/api",
                components: [ComponentVersion(product: "go", label: "Go", version: "1.27", latest: "1.27", status: .current, sources: ["go.mod"])]
            ),
            RepoVersions(
                accountId: gitLabId, repo: "group/app",
                components: [],
                packages: [PackageUse(ecosystem: "PyPI", name: "requests", installs: [
                    PackageInstall(version: "2.31.0", workspace: "", scope: .direct, source: "requirements.txt", requested: "==2.31.0"),
                ])]
            ),
            // Niet meer gevolgd, maar nog in het rapport: mag nergens verschijnen.
            RepoVersions(
                accountId: gitHubId, repo: "acme/old", components: [],
                vulnerabilities: [Vulnerability(
                    id: "GHSA-hidden-0000-0000", cve: nil, summary: "Hidden", severity: "CRITICAL", ecosystem: "npm", package: "hidden",
                    version: "1.0.0", fixedIn: "1.0.1", source: "package-lock.json"
                )]
            ),
        ],
        latestPackages: [
            "npm:express": PackageLatest(version: "5.1.0", seenAt: checkedAt),
            "npm:left-pad": PackageLatest(version: "1.3.0", seenAt: checkedAt),
            "npm:body-parser": PackageLatest(version: "1.20.3", seenAt: checkedAt),
            "PyPI:requests": PackageLatest(version: "2.32.3", seenAt: checkedAt),
        ]
    )
}
