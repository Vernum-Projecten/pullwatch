import Foundation

/// Wat een kwetsbaarheid in één install oplost.
public enum VulnerabilityFix: Hashable, Sendable {
    /// Het package zelf bijwerken: het project vraagt het direct (of dat is niet te bepalen).
    case update(package: String, to: String)
    /// Alleen via de ouder te bereiken: `parent` (het directe package bovenaan de keten) bijwerken,
    /// zodat die `package` op `minimum` of nieuwer binnenhaalt.
    case updateParent(parent: String, package: String, minimum: String)
    /// Geen versie met een oplossing bekend.
    case none
}

extension Vulnerability {
    /// Direct eerst, dan onbekend, dan transitief.
    var scopeRank: Int {
        switch scope {
        case .direct: 0
        case .unknown: 1
        case .transitive: 2
        }
    }

    /// Wat bijgewerkt moet worden om deze install te repareren.
    public var fix: VulnerabilityFix {
        guard let fixedIn else { return .none }
        if scope == .transitive, let parent = via.first {
            return .updateParent(parent: parent, package: package, minimum: fixedIn)
        }
        return .update(package: package, to: fixedIn)
    }
}

/// Eén advies (lek in één package) in een repo, met elke install die het raakt. Een monorepo met
/// hetzelfde lek in de root en in `packages/api` heeft één advies met twee installs.
public struct Advisory: Hashable, Sendable, Identifiable {
    /// Nooit leeg; direct eerst, dan op workspace en versie.
    public let installs: [Vulnerability]

    /// `Vulnerability.key`: OSV-id en package.
    public var id: String { first.key }
    /// De install die het advies vertegenwoordigt: een directe als die er is.
    public var first: Vulnerability { installs[0] }
    /// Het project vraagt het geraakte package ergens zelf.
    public var isDirect: Bool { installs.contains { $0.scope == .direct } }
    /// Elke geraakte install is alleen voor ontwikkelen en testen.
    public var isDevOnly: Bool { installs.allSatisfy { $0.kind == .dev } }
    public var severityRank: Int { installs.map(\.severityRank).max() ?? 0 }
    var scopeRank: Int { installs.map(\.scopeRank).min() ?? 1 }

    /// Groepeert installs per `key`: direct eerst, dan transitief, daarbinnen ernstigste eerst.
    public static func group(_ vulnerabilities: [Vulnerability]) -> [Advisory] {
        var order: [String] = []
        var groups: [String: [Vulnerability]] = [:]
        for vulnerability in vulnerabilities {
            if groups[vulnerability.key] == nil { order.append(vulnerability.key) }
            groups[vulnerability.key, default: []].append(vulnerability)
        }
        let advisories = order.compactMap { key in
            groups[key].map { installs in
                Advisory(installs: installs.sorted {
                    if $0.scopeRank != $1.scopeRank { return $0.scopeRank < $1.scopeRank }
                    if $0.workspace != $1.workspace { return $0.workspace.isEmpty || (!$1.workspace.isEmpty && $0.workspace < $1.workspace) }
                    return VersionChecker.isOlder($0.version, than: $1.version)
                })
            }
        }
        return advisories.sorted {
            if $0.scopeRank != $1.scopeRank { return $0.scopeRank < $1.scopeRank }
            if $0.severityRank != $1.severityRank { return $0.severityRank > $1.severityRank }
            return ($0.first.package, $0.first.id) < ($1.first.package, $1.first.id)
        }
    }
}

/// Eén package in één workspace van een repo, met zijn installs daar.
public struct WorkspacePackage: Hashable, Sendable, Identifiable {
    public let ecosystem: String
    public let name: String
    /// Nooit leeg; direct eerst, dan oudste versie eerst.
    public let installs: [PackageInstall]
    /// Alle versies van dit package in de hele repo (over alle workspaces), oudste eerst.
    public let repoVersions: [String]

    /// `PackageUse.key`.
    public var id: String { "\(ecosystem):\(name)" }
}

/// De packages van één workspace (map met een manifest of lockfile; "" is de root), ingedeeld
/// naar hoe ze erin komen.
public struct PackageWorkspace: Hashable, Sendable, Identifiable {
    public let workspace: String
    /// Runtime en optioneel, met minstens één directe install.
    public let direct: [WorkspacePackage]
    /// Runtime en optioneel, alleen via een ander package.
    public let transitive: [WorkspacePackage]
    /// Runtime en optioneel, zonder manifest om direct of transitief te bepalen.
    public let unknown: [WorkspacePackage]
    /// Alleen voor ontwikkelen en testen, direct of transitief.
    public let dev: [WorkspacePackage]

    public var id: String { workspace }
    public var isEmpty: Bool { direct.isEmpty && transitive.isEmpty && unknown.isEmpty && dev.isEmpty }
}

extension RepoVersions {
    /// De kwetsbaarheden per advies; zie `Advisory.group`.
    public var advisories: [Advisory] { Advisory.group(vulnerabilities) }

    /// Packages per workspace, de root eerst, dan op naam; binnen een workspace elk package op naam.
    public var packageWorkspaces: [PackageWorkspace] {
        let all = packages + otherPackages
        var byWorkspace: [String: [WorkspacePackage]] = [:]
        for package in all {
            let versions = package.versions
            for (workspace, installs) in Dictionary(grouping: package.installs, by: \.workspace) {
                let sorted = installs.sorted {
                    if ($0.scope == .direct) != ($1.scope == .direct) { return $0.scope == .direct }
                    return VersionChecker.isOlder($0.version, than: $1.version)
                }
                byWorkspace[workspace, default: []].append(
                    WorkspacePackage(ecosystem: package.ecosystem, name: package.name, installs: sorted, repoVersions: versions)
                )
            }
        }
        return byWorkspace.keys.sorted { $0.isEmpty || (!$1.isEmpty && $0.localizedStandardCompare($1) == .orderedAscending) }.map { workspace in
            let packages = (byWorkspace[workspace] ?? []).sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            var direct: [WorkspacePackage] = [], transitive: [WorkspacePackage] = []
            var unknown: [WorkspacePackage] = [], dev: [WorkspacePackage] = []
            for package in packages {
                if package.installs.allSatisfy({ $0.kind == .dev }) {
                    dev.append(package)
                } else if package.installs.contains(where: { $0.scope == .direct }) {
                    direct.append(package)
                } else if package.installs.allSatisfy({ $0.scope == .transitive }) {
                    transitive.append(package)
                } else {
                    unknown.append(package)
                }
            }
            return PackageWorkspace(workspace: workspace, direct: direct, transitive: transitive, unknown: unknown, dev: dev)
        }
    }
}

extension PackageUser {
    /// De repo heeft het package alleen via andere packages: niet zelf bij te werken.
    public var isTransitiveOnly: Bool {
        !installs.isEmpty && installs.allSatisfy { $0.scope == .transitive }
    }
}
