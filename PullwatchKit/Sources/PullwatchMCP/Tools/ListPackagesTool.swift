import Foundation
import MCP
import PullwatchCore

/// `list_packages`: wat de gevolgde repo's (en bij Azure Artifacts de projecten) zelf publiceren in
/// het register van hun dienst, één per package, met de recente versies en de gevolgde repo's die
/// het gebruiken. Een bron die uit staat of een account zonder recht staat apart, nooit als "niets
/// gepubliceerd".
enum ListPackagesTool {
    static let name = "list_packages"

    struct Version: Encodable {
        let version: String
        let publishedAt: Date?
        let url: URL?
        let tag: String?
        let runUrl: URL?
    }

    struct User: Encodable {
        let repository: String
        let versions: [String]
        let isDirect: Bool
    }

    struct PackageItem: Encodable {
        let name: String
        let type: String
        let accountId: UUID
        let owner: String
        let repository: String?
        let latestVersion: String?
        let publishedAt: Date?
        let visibility: String?
        let url: URL?
        let recentVersions: [Version]
        let usedBy: [User]
        /// Of de check gebruikers van dit soort package kan herkennen.
        let usageKnown: Bool
    }

    struct NeedsPermission: Encodable {
        let accountId: UUID
        let reason: String
    }

    struct Output: Encodable {
        let packages: [PackageItem]
        let total: Int
        let nextCursor: String?
        let notChecked: [MCPSourceOff]
        let needsPermission: [NeedsPermission]
    }

    static func make(_ source: any MCPDataSource) -> MCPTool {
        MCPTool(
            name: name,
            title: "List published packages",
            description: """
                Lists the packages the followed repositories publish to the registry of their own service (GitHub Packages, \
                a GitLab package or container registry, an Azure Artifacts feed), one per package: type, owner, the \
                publishing repository (absent for Azure Artifacts, where the owner is the feed's project), the latest version \
                and its date, the recent versions with their tag and pipeline when the service says, and which followed \
                repositories depend on it with their versions. Use it for "what does acme/ui publish?" or "who is still on \
                an old @acme/ui?". not_checked and needs_permission list what Pullwatch could not read: never report those \
                as publishing nothing. Filters: repo, type, account_id. Paged with limit and cursor.
                """,
            input: .object(
                [
                    "repo": .string("Only packages published by this followed repository (owner/name).", maxLength: 300),
                    "type": .string("Only this package type (npm, container, nuget, maven, rubygems, pypi, helm, generic, ...).", maxLength: 40),
                    "account_id": .string("Only this account (an id from get_status).", maxLength: 64),
                ].merging(MCPPaging.inputFields) { first, _ in first }
            ),
            output: .object(
                [
                    "packages": .array(of: .object(
                        [
                            "name": .string("The name in the registry."),
                            "type": .string("The package type as the service names it."),
                            "account_id": .string(),
                            "owner": .string("The user, organization, group or Azure DevOps project it belongs to."),
                            "repository": .string("The followed repository that publishes it; absent when the service ties it to none."),
                            "latest_version": .string(),
                            "published_at": .dateTime("When the latest version was published."),
                            "visibility": .string(oneOf: ["public", "private", "internal"]),
                            "url": .string("The package page in the registry."),
                            "recent_versions": .array(of: .object(
                                [
                                    "version": .string(), "published_at": .dateTime("When it was published."), "url": .string(),
                                    "tag": .string("The repository tag of this version."), "run_url": .string("The run or pipeline that published it."),
                                ],
                                required: ["version"]
                            ), "Newest first, at most 10."),
                            "used_by": .array(of: .object(
                                [
                                    "repository": .string(),
                                    "versions": .array(of: .string(), "Installed versions, oldest first."),
                                    "is_direct": .boolean("Whether the repository asks for it itself."),
                                ],
                                required: ["repository", "versions", "is_direct"]
                            ), "Followed repositories that depend on it."),
                            "usage_known": .boolean("false for types the dependency check does not match yet (container images, Helm charts): used_by is then unknown, not empty."),
                        ],
                        required: ["name", "type", "account_id", "owner", "recent_versions", "used_by", "usage_known"]
                    )),
                    "not_checked": .array(of: MCPSourceOff.schema),
                    "needs_permission": .array(of: .object(
                        ["account_id": .string(), "reason": .string("What the account needs to read its registry.")],
                        required: ["account_id", "reason"]
                    ), "Accounts whose registry Pullwatch may not read: their packages are unknown."),
                ].merging(MCPPaging.outputFields) { first, _ in first },
                required: ["packages", "total", "not_checked", "needs_permission"]
            )
        ) { arguments in
            try await run(arguments, source: source)
        }
    }

    static func run(_ arguments: MCPArguments, source: any MCPDataSource) async throws -> MCPToolResult {
        let paging = try MCPPaging(arguments)
        let accounts = await source.accounts()
        let followed = MCPFollowedRepos(accounts: accounts, summaries: await source.repoSummaries(), history: await source.historyItems())
        let accountIds = Set(try MCPFollowedRepos.accounts(accounts, matching: arguments.string("account_id")).map(\.id))
        var repository: MCPFollowedRepos.Match?
        if let repo = arguments.string("repo") {
            repository = try followed.resolve(repo, accountId: arguments.string("account_id"))
        }
        let type = arguments.string("type").map { PublishedPackageType(rawValue: $0) }

        guard !(await source.disabledSources()).contains(.packageRegistries) else {
            let output = Output(packages: [], total: 0, nextCursor: nil, notChecked: [MCPSourceOff(.packageRegistries)], needsPermission: [])
            return try MCPToolOutput.result(output, summary: "Not checked: source \(MCPSourceOff.name(.packageRegistries)) is off.")
        }
        let report = await source.versionReport()
        let results = (report?.publishedPackages ?? []).filter { accountIds.contains($0.accountId) }
        let needsPermission = results.compactMap { result -> NeedsPermission? in
            guard case .needsPermission(let reason) = result.result else { return nil }
            return NeedsPermission(accountId: result.accountId, reason: reason)
        }
        let summaries = (report?.publishedPackageSummaries() ?? []).filter { summary in
            let package = summary.package
            guard accountIds.contains(package.accountId) else { return false }
            // Alleen wat bij een gevolgde repo hoort; een package zonder repo (Azure) bij een gevolgd account.
            if let repo = package.repository, !followed.contains(accountId: package.accountId, repo: repo) { return false }
            if let type, package.type != type { return false }
            if let repository {
                return package.accountId == repository.account.id
                    && package.repository?.caseInsensitiveCompare(repository.repo) == .orderedSame
            }
            return true
        }
        let items = summaries.map { item($0, followed: followed) }
        let page = paging.page(items)
        var summary = "\(MCPToolOutput.count(items.count, "published package"))."
        if !needsPermission.isEmpty { summary += " Some accounts may not read their registry; see needs_permission." }
        let output = Output(
            packages: page.items, total: items.count, nextCursor: page.nextCursor, notChecked: [], needsPermission: needsPermission
        )
        return try MCPToolOutput.result(output, summary: summary)
    }

    private static func item(_ summary: PublishedPackageSummary, followed: MCPFollowedRepos) -> PackageItem {
        let package = summary.package
        return PackageItem(
            name: package.name, type: package.type.rawValue, accountId: package.accountId, owner: package.owner,
            repository: package.repository, latestVersion: package.latestVersion, publishedAt: package.publishedAt,
            visibility: package.visibility?.rawValue, url: package.webURL?.withoutCredentials,
            recentVersions: package.versions.map {
                Version(version: $0.version, publishedAt: $0.publishedAt, url: $0.webURL?.withoutCredentials, tag: $0.tag, runUrl: $0.runURL?.withoutCredentials)
            },
            usedBy: summary.users
                .filter { followed.contains(accountId: $0.accountId, repo: $0.repo) }
                .map { User(repository: $0.repo, versions: $0.versions, isDirect: $0.isDirect) },
            usageKnown: summary.isMatchable
        )
    }
}
