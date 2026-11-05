import Foundation
import MCP
import PullwatchCore

/// `explain_update`: wat het bijwerken van één package in één gevolgde repo tegenhoudt, per
/// install, uit de blokkades van de versiecheck (ouder, peer, runtime, gevraagd bereik), met de
/// kwetsbaarheden die de update zou oplossen.
enum ExplainUpdateTool {
    static let name = "explain_update"

    struct Blocker: Encodable {
        let kind: String
        let name: String
        let needs: String?
        let installed: String?
        let minimumVersion: String?
    }

    struct Install: Encodable {
        let workspace: String
        let version: String
        let scope: String
        let use: String
        let via: [String]
        let requested: String?
        let declaredIn: String
        let update: String
        let unknownReason: String?
        let step: String?
        let usableVersion: String?
        let blocker: Blocker?
        let explanation: String
    }

    struct Fix: Encodable {
        let id: String
        let severity: String
        let fixedIn: String?
        let fix: String
    }

    struct Output: Encodable {
        let repository: String
        let accountId: UUID
        let package: String
        let ecosystem: String
        let latest: String?
        /// Gezet als een gevolgde repository het package zelf publiceert.
        let inHouse: MCPInHouse?
        let installs: [Install]
        let vulnerabilities: [Fix]
        let notChecked: [MCPSourceOff]
    }

    static let updateValues = ["up_to_date", "within_range", "needs_manifest_change", "blocked", "unknown", "not_checked"]

    static func make(_ source: any MCPDataSource) -> MCPTool {
        MCPTool(
            name: name,
            title: "Explain a package update",
            description: """
                Explains what blocks updating one package in one followed repository, per install: whether the latest \
                version is within the requested range, needs a manifest change, or is held back by a parent package, a peer \
                or the runtime (with the version to update that to first), the newest version that works now, and the \
                vulnerabilities in the package with their fix. Works for transitive packages too (any package from a lock \
                file): via names the chain from the direct dependency, and the explanation says what must change to fix a \
                vulnerability (only the lock file, or the parent first, within or outside its own range). Use it for "why can't I update react in acme/web?" before \
                changing manifests. Needs repo and package; pass ecosystem when the repository uses two packages with the \
                same name. Reads Pullwatch's last version check; it does not look up anything new.
                """,
            input: .object(
                [
                    "repo": .string("The followed repository (owner/name; project/repo on Azure DevOps).", maxLength: 300),
                    "package": .string("The package name as in the manifest (case does not matter).", maxLength: 300),
                    "ecosystem": .string("go, npm, composer, nuget, pypi, cargo, gem or swift; only needed when the name is ambiguous.", maxLength: 40),
                    "account_id": .string("The account (an id from get_status); only needed when two accounts follow a repository with this name.", maxLength: 64),
                ],
                required: ["repo", "package"]
            ),
            output: .object(
                [
                    "repository": .string(), "account_id": .string(), "package": .string(), "ecosystem": .string(),
                    "latest": .string(
                        "The latest version in the registry (your own registry for an in-house package); absent when unknown or the registry source is off."
                    ),
                    "in_house": MCPInHouse.schema,
                    "installs": .array(of: .object(
                        [
                            "workspace": .string("Empty for the repository root."), "version": .string(),
                            "scope": .string(oneOf: ["direct", "transitive", "unknown"]),
                            "use": .string(oneOf: ["runtime", "dev", "optional"]),
                            "via": .array(of: .string(), "The chain of packages that pulls a transitive install in."),
                            "requested": .string(
                                "The requested range: from the manifest, or for a transitive install the range its parent (the last package in via) asks for."
                            ),
                            "declared_in": .string(),
                            "update": .string(oneOf: updateValues),
                            "unknown_reason": .string("Why update is unknown.", oneOf: MCPUpdateText.unknownReasons),
                            "step": .string(oneOf: ["patch", "minor", "major"]),
                            "usable_version": .string("The newest version every requirement allows now."),
                            "blocker": .object(
                                [
                                    "kind": .string(oneOf: ["package", "peer", "runtime"]), "name": .string(),
                                    "needs": .string("The range it asks for."), "installed": .string(),
                                    "minimum_version": .string("The lowest version of the blocking package that allows the update."),
                                ],
                                required: ["kind", "name"]
                            ),
                            "explanation": .string("The answer as a sentence."),
                        ],
                        required: ["workspace", "version", "scope", "use", "via", "declared_in", "update", "explanation"]
                    )),
                    "vulnerabilities": .array(of: .object(
                        ["id": .string(), "severity": .string(oneOf: ListVulnerabilitiesTool.severities), "fixed_in": .string(), "fix": .string()],
                        required: ["id", "severity", "fix"]
                    ), "Known vulnerabilities in the installed versions."),
                    "not_checked": .array(of: MCPSourceOff.schema),
                ],
                required: ["repository", "account_id", "package", "ecosystem", "installs", "vulnerabilities", "not_checked"]
            )
        ) { arguments in
            try await run(arguments, source: source)
        }
    }

    static func run(_ arguments: MCPArguments, source: any MCPDataSource) async throws -> MCPToolResult {
        let followed = MCPFollowedRepos(accounts: await source.accounts(), summaries: await source.repoSummaries(), history: await source.historyItems())
        let match = try followed.resolve(arguments.string("repo") ?? "", accountId: arguments.string("account_id"))
        guard let summary = match.summary, let versions = summary.versions else {
            throw MCPToolError("Pullwatch has not checked \(match.repo) yet, so it knows nothing about its packages.")
        }
        if let error = versions.error {
            throw MCPToolError("The last check of \(match.repo) failed, so it knows nothing about its packages: \(error)")
        }
        let name = arguments.string("package") ?? ""
        let ecosystem = arguments.string("ecosystem")
        let uses = (versions.packages + versions.otherPackages).filter {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
                && (ecosystem == nil || PackageVersions.kind(ofEcosystem: $0.ecosystem).caseInsensitiveCompare(ecosystem ?? "") == .orderedSame)
        }
        let report = await source.versionReport()
        guard let use = uses.first else {
            // Een rapport van een oudere check kent geen transitieve packages: zeg dat, in plaats van "gebruikt het niet".
            let older = report?.isOutdatedFormat == true
                ? " That check was made by an older version of Pullwatch, which kept only the direct packages; Pullwatch checks again by itself."
                : ""
            throw MCPToolError(
                "\(match.repo) does not use a package named \(name) in Pullwatch's last check.\(older) get_repository_report lists its packages."
            )
        }
        guard uses.count == 1 else {
            let kinds = uses.map { PackageVersions.kind(ofEcosystem: $0.ecosystem) }.joined(separator: ", ")
            throw MCPToolError("\(match.repo) uses \(name) from more than one ecosystem (\(kinds)); pass ecosystem to choose one.")
        }

        var notChecked: [MCPSourceOff] = []
        let context = await source.updateContext(for: versions)
        // Een eigen package: de nieuwste versie komt uit het eigen register, en alleen die bron telt.
        let inHouse = context.metadata[use.key]?.inHouse.map(MCPInHouse.init)
        let registryOff: Bool
        if let inHouse {
            let off = inHouse.notChecked(repository: match.repo)
            registryOff = off != nil
            if let off { notChecked.append(off) }
        } else {
            let registry = DataSourceID.registry(ecosystem: use.ecosystem)
            registryOff = registry.map(versions.isUnchecked) ?? false
            if let registry, registryOff { notChecked.append(MCPSourceOff(registry, repository: match.repo)) }
        }
        if versions.isUnchecked(.osv) { notChecked.append(MCPSourceOff(.osv, repository: match.repo)) }
        let latest = registryOff ? nil : report?.latestPackages[use.key]?.version
        let installs = use.installs.map { item in
            install(use, item, latest: latest, registryOff: registryOff, inHouse: inHouse, context: context, versions: versions)
        }
        let vulnerabilities = versions.vulnerabilityRows(gitHub: summary.advisories, context: context)
            .filter { $0.package.caseInsensitiveCompare(use.name) == .orderedSame && $0.first.ecosystem == use.ecosystem }
            .map { row in
                Fix(id: row.primaryId, severity: ListVulnerabilitiesTool.severities[row.severity.rawValue], fixedIn: row.fixedIn,
                    fix: row.fixes.map(AgentBrief.fixText).joined(separator: " "))
            }
        let output = Output(
            repository: match.repo, accountId: match.account.id, package: use.name, ecosystem: PackageVersions.kind(ofEcosystem: use.ecosystem),
            latest: latest, inHouse: inHouse, installs: installs, vulnerabilities: vulnerabilities, notChecked: notChecked
        )
        let own = inHouse.map { "\(use.name) is in-house: \($0.source) publishes it, so its latest version comes from your own registry. " } ?? ""
        let summaryText = registryOff
            ? "\(own)\(use.name) in \(match.repo): \(notChecked[0].message)"
            : own + installs.map(\.explanation).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: " ")
        return try MCPToolOutput.result(output, summary: summaryText)
    }

    private static func install(
        _ use: PackageUse, _ install: PackageInstall, latest: String?, registryOff: Bool, inHouse: MCPInHouse?, context: UpdateContext,
        versions: RepoVersions
    ) -> Install {
        let scope = install.scope.rawValue
        let place = install.workspace.isEmpty ? "the root" : install.workspace
        let requested = context.requirement(ecosystem: use.ecosystem, name: use.name, install: install)
        let parent = install.scope == .transitive ? install.via.last : nil
        guard !registryOff else {
            return Install(
                workspace: install.workspace, version: install.version, scope: scope, use: install.kind.rawValue, via: install.via,
                requested: requested, declaredIn: install.source, update: "not_checked", unknownReason: nil, step: nil, usableVersion: nil,
                blocker: nil,
                explanation: inHouse?.status == "needs_permission"
                    ? "\(use.name) \(install.version) in \(place): the latest version is not checked because Pullwatch may not read the package registry that publishes it."
                    : inHouse?.status == "read_failed"
                    ? "\(use.name) \(install.version) in \(place): the latest version is not checked because reading it from the package registry that publishes it failed."
                    : inHouse != nil
                        ? "\(use.name) \(install.version) in \(place): the latest version is not checked because the source Package registries of your accounts is off."
                        : "\(use.name) \(install.version) in \(place): the latest version is not checked because its registry source is off."
            )
        }
        let update = PackageUpdate(ecosystem: use.ecosystem, name: use.name, install: install, latest: latest, context: context)
        var explanation: String
        if let sentence = AgentBrief.blockerSentence(package: use.name, installed: install.version, requested: requested, update: update) {
            explanation = sentence
        } else {
            switch update.status {
            case .upToDate:
                explanation = "\(use.name) \(install.version) in \(place) is the latest version."
            case .withinRange:
                explanation = "\(use.name) \(latest ?? "") is within the requested range \(requested ?? ""); only the lock file changes."
            default:
                let cause = update.unknownReason.map { MCPUpdateText.cause($0, parent: parent) } ?? "the status is not known"
                explanation = update.unknownReason == .latestNotLookedUp
                    ? "Its latest version is not known: \(cause)."
                    : "Pullwatch cannot tell whether \(use.name) \(install.version) in \(place) can be updated: \(cause)."
            }
        }
        if parent != nil {
            let asks = requested.map { "; \(install.via.last ?? "") asks for \(use.name) \($0)" } ?? ""
            explanation = "\(use.name) \(install.version) in \(place) comes in through \(install.via.joined(separator: " > "))\(asks). " + explanation
        }
        explanation += transitiveFixes(use, install, requested: requested, context: context, versions: versions).map { " " + $0 }.joined()
        return Install(
            workspace: install.workspace, version: install.version, scope: scope, use: install.kind.rawValue, via: install.via,
            requested: requested, declaredIn: install.source, update: MCPUpdateText.status(update.status),
            unknownReason: MCPUpdateText.reason(update.unknownReason), step: MCPUpdateText.step(update.step),
            usableVersion: update.usable.flatMap { $0 == update.latest || $0 == install.version ? nil : $0 },
            blocker: blocker(update.status), explanation: explanation
        )
    }

    /// Wat er voor een transitieve install moet veranderen om elke kwetsbaarheid erin op te lossen:
    /// alleen de lockfile (de oplossing valt binnen wat de ouder vraagt), of eerst de ouder, binnen
    /// of buiten zijn eigen bereik.
    private static func transitiveFixes(
        _ use: PackageUse, _ install: PackageInstall, requested: String?, context: UpdateContext, versions: RepoVersions
    ) -> [String] {
        guard install.scope == .transitive else { return [] }
        let found = versions.vulnerabilities.filter {
            $0.ecosystem == use.ecosystem && $0.package == use.name && $0.version == install.version && $0.workspace == install.workspace
        }
        var seen: Set<String> = []
        return found.compactMap { vulnerability -> String? in
            guard seen.insert(vulnerability.id).inserted, let fixedIn = vulnerability.fixedIn else { return nil }
            let id = vulnerability.id
            switch vulnerability.fix(in: context) {
            case .withinRange:
                let command = use.ecosystem == "crates.io" ? " (cargo update -p \(use.name))" : ""
                let range = requested.map { " \($0)" } ?? ""
                return "To fix \(id), \(use.name) \(fixedIn) is within the range\(range) that \(install.via.last ?? "its parent") asks for, "
                    + "so only the lock file changes\(command)."
            case .blocked(_, _, .package(let blocking, let range, let minimum)):
                guard let minimum else {
                    return "To fix \(id), \(blocking) must allow \(use.name) \(fixedIn), but it asks for \(range) and no known version of \(blocking) allows it yet."
                }
                return "To fix \(id), update \(blocking) to \(minimum) first: it asks for \(use.name) \(range), which does not allow \(fixedIn)."
                    + parentRange(blocking, minimum: minimum, ecosystem: use.ecosystem, versions: versions)
            case let fix:
                return "To fix \(id): " + AgentBrief.fixText(fix)
            }
        }
    }

    /// Of de nieuwe versie van de ouder binnen zijn eigen gevraagde bereik valt.
    private static func parentRange(_ parent: String, minimum: String, ecosystem: String, versions: RepoVersions) -> String {
        let installs = (versions.packages + versions.otherPackages).first { $0.ecosystem == ecosystem && $0.name == parent }?.installs ?? []
        guard let direct = installs.first(where: { $0.scope == .direct }), let requested = direct.requested,
              let allows = direct.requestedAllows(minimum, ecosystem: ecosystem, name: parent) else { return "" }
        return allows
            ? " \(minimum) is within the range \(requested) the manifest asks for \(parent), so only the lock file changes."
            : " \(minimum) is outside the range \(requested) the manifest asks for \(parent), so the manifest changes too."
    }

    private static func blocker(_ status: PackageUpdate.Status) -> Blocker? {
        switch status {
        case .blockedByPackage(let parent, let range, let minimum):
            Blocker(kind: "package", name: parent, needs: range, installed: nil, minimumVersion: minimum)
        case .blockedByPeer(let name, let needs, let installed):
            Blocker(kind: "peer", name: name, needs: needs, installed: installed, minimumVersion: nil)
        case .blockedByRuntime(let runtime, let needs, let installed):
            Blocker(kind: "runtime", name: runtime, needs: needs, installed: installed, minimumVersion: nil)
        case .upToDate, .withinRange, .needsManifestChange, .unknown:
            nil
        }
    }
}
