import Foundation
import MCP
import PullwatchCore

/// `get_repository_report`: de versiecheck van één gevolgde repo: runtimes en frameworks met hun
/// status, en de packages met hun nieuwste versie en wat een update tegenhoudt.
enum GetRepositoryReportTool {
    static let name = "get_repository_report"

    struct Runtime: Encodable {
        let name: String
        let product: String
        let version: String
        let latest: String?
        let status: String
        let declaredIn: [String]
    }

    struct Package: Encodable {
        let name: String
        let ecosystem: String
        let workspace: String
        let group: String
        let installed: [String]
        let latest: String?
        let update: String
        let unknownReason: String?
        let usableVersion: String?
        let blocker: String?
        let declaredIn: [String]
        let requested: [String]
        /// Transitief: de keten vanaf het directe package.
        let via: [String]?
        /// Gezet als een gevolgde repository het package zelf publiceert.
        let inHouse: MCPInHouse?
    }

    struct Release: Encodable {
        let tag: String
        let error: String?
    }

    struct Output: Encodable {
        let repository: String
        let accountId: UUID
        let url: URL?
        let health: String
        let checked: Bool
        let checkedAt: Date?
        let checkError: String?
        let runtimes: [Runtime]
        let latestRelease: Release?
        let packages: [Package]
        let total: Int
        let nextCursor: String?
        let notChecked: [MCPSourceOff]
    }

    static let updateValues = ["up_to_date", "within_range", "needs_manifest_change", "blocked", "unknown", "not_checked"]
    static let statusValues = ["current", "behind", "end_of_life", "unknown", "not_checked"]

    static func make(_ source: any MCPDataSource) -> MCPTool {
        MCPTool(
            name: name,
            title: "Get a repository report",
            description: """
                Returns the version check of one followed repository: its runtimes and frameworks (version, latest, status \
                current, behind, end_of_life, unknown or not_checked) and its packages per workspace with the installed and \
                latest version and whether an update is up_to_date, within_range (only the lock file changes), \
                needs_manifest_change, blocked (with the blocker), unknown or not_checked. Use it to see how far behind a \
                repository is before planning upgrades; use list_vulnerabilities for vulnerabilities and explain_update for \
                one package (direct or transitive). Transitive packages come with group transitive and via; Pullwatch looks up \
                the latest version only for direct packages, so their update is unknown. checked false means Pullwatch has not checked the repository yet. Packages are paged with limit \
                and cursor; only_outdated keeps the packages with a newer version.
                """,
            input: .object(
                [
                    "repo": .string("The followed repository (owner/name; project/repo on Azure DevOps).", maxLength: 300),
                    "account_id": .string("The account (an id from get_status); only needed when two accounts follow a repository with this name.", maxLength: 64),
                    "only_outdated": .boolean("true: only packages whose latest version is newer than the installed one."),
                ].merging(MCPPaging.inputFields) { first, _ in first },
                required: ["repo"]
            ),
            output: .object(
                [
                    "repository": .string(),
                    "account_id": .string(),
                    "url": .string(),
                    "health": .string(oneOf: ListRepositoriesTool.healthValues),
                    "checked": .boolean("Whether the version check has run for this repository."),
                    "checked_at": .dateTime("When the last full version check ran."),
                    "check_error": .string("Why the check failed; then the lists say nothing."),
                    "runtimes": .array(of: .object(
                        [
                            "name": .string(), "product": .string("The product id at endoflife.date or swift.org."),
                            "version": .string(), "latest": .string(),
                            "status": .string(oneOf: statusValues),
                            "declared_in": .array(of: .string(), "The files that declare it."),
                        ],
                        required: ["name", "product", "version", "status", "declared_in"]
                    )),
                    "latest_release": .object(
                        ["tag": .string(), "error": .string("Why the tag could not be checked.")],
                        required: ["tag"], "The newest version tag, checked the same way."
                    ),
                    "packages": .array(of: .object(
                        [
                            "name": .string(), "ecosystem": .string("go, npm, composer, nuget, pypi, cargo, gem or swift."),
                            "workspace": .string("The folder of the workspace; empty for the repository root."),
                            "group": .string(oneOf: ["direct", "transitive", "unknown", "dev"]),
                            "installed": .array(of: .string()), "latest": .string(),
                            "update": .string(oneOf: updateValues),
                            "unknown_reason": .string("Why update is unknown.", oneOf: MCPUpdateText.unknownReasons),
                            "via": .array(of: .string(), "For a transitive package: the chain from the direct dependency that pulls it in."),
                            "usable_version": .string("The newest version that works now, when it differs from latest."),
                            "blocker": .string("What holds the update back, as a sentence."),
                            "declared_in": .array(of: .string()), "requested": .array(of: .string("A requested range from the manifest.")),
                            "in_house": MCPInHouse.schema,
                        ],
                        required: ["name", "ecosystem", "workspace", "group", "installed", "update", "declared_in", "requested"]
                    )),
                    "not_checked": .array(of: MCPSourceOff.schema),
                ].merging(MCPPaging.outputFields) { first, _ in first },
                required: ["repository", "account_id", "health", "checked", "runtimes", "packages", "total", "not_checked"]
            )
        ) { arguments in
            try await run(arguments, source: source)
        }
    }

    static func run(_ arguments: MCPArguments, source: any MCPDataSource) async throws -> MCPToolResult {
        let paging = try MCPPaging(arguments)
        let followed = MCPFollowedRepos(accounts: await source.accounts(), summaries: await source.repoSummaries(), history: await source.historyItems())
        let match = try followed.resolve(arguments.string("repo") ?? "", accountId: arguments.string("account_id"))
        let report = await source.versionReport()
        let health = match.summary.map { ListRepositoriesTool.healthText($0.health) } ?? "unknown"
        guard let versions = match.summary?.versions else {
            let output = Output(
                repository: match.repo, accountId: match.account.id, url: match.account.safeRepoWebURL(match.repo), health: health,
                checked: false, checkedAt: report?.checkedAt, checkError: nil, runtimes: [], latestRelease: nil, packages: [], total: 0,
                nextCursor: nil, notChecked: []
            )
            return try MCPToolOutput.result(output, summary: "\(match.repo) has not been checked yet, so nothing is known about its versions.")
        }
        let context = await source.updateContext(for: versions)
        let runtimes = versions.error == nil ? versions.components.map { runtime($0, versions: versions) } : []
        var packages: [Package] = []
        if versions.error == nil {
            for workspace in versions.packageWorkspaces {
                let groups = [("direct", workspace.direct), ("transitive", workspace.transitive), ("unknown", workspace.unknown), ("dev", workspace.dev)]
                for (group, items) in groups {
                    packages += items.map { package($0, workspace: workspace.workspace, group: group, versions: versions, report: report, context: context) }
                }
            }
        }
        if arguments.boolean("only_outdated") == true {
            packages = packages.filter { $0.update != "up_to_date" && $0.update != "unknown" && $0.update != "not_checked" }
        }
        let page = paging.page(packages)
        let output = Output(
            repository: match.repo, accountId: match.account.id, url: match.account.safeRepoWebURL(match.repo), health: health,
            checked: true, checkedAt: report?.checkedAt, checkError: versions.error, runtimes: runtimes,
            latestRelease: versions.release.map { Release(tag: $0.tag, error: $0.error) },
            packages: page.items, total: packages.count, nextCursor: page.nextCursor,
            notChecked: MCPSourceOff.skipped(versions) + permissionsMissing(packages, repository: match.repo)
        )
        if let error = versions.error {
            return try MCPToolOutput.result(output, summary: "The check of \(match.repo) failed: \(error)")
        }
        let outdated = runtimes.filter { $0.status == "behind" || $0.status == "end_of_life" }.count
        let summary = "\(match.repo): \(MCPToolOutput.count(runtimes.count, "runtime")) (\(outdated) behind or end of life), "
            + "\(MCPToolOutput.count(packages.count, "package")) listed."
            + (output.notChecked.isEmpty ? "" : " Some sources were off; see not_checked.")
            + (report?.isOutdatedFormat == true
                ? " This check was made by an older version of Pullwatch, which kept only the direct packages; Pullwatch checks again by itself."
                : "")
        return try MCPToolOutput.result(output, summary: summary)
    }

    /// Eigen packages die het account niet mocht lezen, één regel per reden.
    private static func permissionsMissing(_ packages: [Package], repository: String) -> [MCPSourceOff] {
        packages.compactMap(\.inHouse).filter { $0.status == "needs_permission" }
            .compactMap { $0.notChecked(repository: repository) }
            .reduce(into: [MCPSourceOff]()) { if !$0.contains($1) { $0.append($1) } }
    }

    private static func runtime(_ component: ComponentVersion, versions: RepoVersions) -> Runtime {
        let off = versions.isUnchecked(DataSourceID.releases(product: component.product))
        let status = switch component.status {
        case .current: "current"
        case .behind: "behind"
        case .eol: "end_of_life"
        case .unknown: "unknown"
        }
        return Runtime(
            name: component.label, product: component.product, version: component.version, latest: off ? nil : component.latest,
            status: off ? "not_checked" : status, declaredIn: component.sources
        )
    }

    private static func package(
        _ package: WorkspacePackage, workspace: String, group: String, versions: RepoVersions, report: VersionReport?, context: UpdateContext
    ) -> Package {
        // Een eigen package hangt aan het eigen register, niet aan het publieke van zijn ecosysteem.
        let inHouse = context.metadata[package.id]?.inHouse
        let registryOff = inHouse.map { !$0.isChecked }
            ?? DataSourceID.registry(ecosystem: package.ecosystem).map(versions.isUnchecked) ?? false
        let latest = registryOff ? nil : report?.latestPackages[package.id]?.version
        let installs = package.installs
        let installed = installs.map(\.version).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let requested = installs.compactMap(\.requested).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let declaredIn = installs.map(\.source).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        var updateText = "not_checked"
        var usable: String?
        var blocker: String?
        var reason: String?
        if !registryOff {
            let updates = installs.map { PackageUpdate(ecosystem: package.ecosystem, name: package.name, install: $0, latest: latest, context: context) }
            let combined = PackageUpdate.combined(updates)
            updateText = combined.map { MCPUpdateText.status($0.status) } ?? "unknown"
            reason = MCPUpdateText.reason(combined?.unknownReason)
            if let combined, let found = combined.usable, found != combined.latest { usable = found }
            blocker = zip(installs, updates).lazy.compactMap { install, update in
                AgentBrief.blockerSentence(package: package.name, installed: install.version, requested: install.requested, update: update)
            }.first
        }
        return Package(
            name: package.name, ecosystem: PackageVersions.kind(ofEcosystem: package.ecosystem), workspace: workspace, group: group,
            installed: installed, latest: latest, update: updateText, unknownReason: reason, usableVersion: usable, blocker: blocker,
            declaredIn: declaredIn, requested: requested,
            via: group == "transitive" ? installs.first { $0.scope == .transitive }?.via : nil,
            inHouse: inHouse.map(MCPInHouse.init)
        )
    }
}
