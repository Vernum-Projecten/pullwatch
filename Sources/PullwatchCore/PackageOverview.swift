import Foundation

/// Nieuwste versie van een package in zijn register; `version` nil als die niet op te halen was.
public struct PackageLatest: Codable, Hashable, Sendable {
    public let version: String?
    /// Eerste check waarin deze versie de nieuwste was.
    public let seenAt: Date

    public init(version: String?, seenAt: Date) {
        self.version = version
        self.seenAt = seenAt
    }
}

/// Eén repo die een package of runtime-cyclus gebruikt.
public struct PackageUser: Hashable, Sendable, Identifiable {
    public let repoId: String
    public let repo: String
    public let version: String
    public let sources: [String]

    public var id: String { repoId }
}

/// Eén regel in het onderdeel Versies: een library, of een runtime binnen één cyclus ("Go 1.27").
public struct PackageSummary: Hashable, Sendable, Identifiable {
    public enum State: Hashable, Sendable {
        case updateAvailable, current, unchecked
    }

    /// `PackageUse.key` voor libraries, "runtime:<product>:<cyclus>" voor runtimes.
    public let id: String
    public let label: String
    /// "runtime" of het ecosysteem zoals een ontwikkelaar het kent: go, npm, composer, nuget, pypi, cargo, swift.
    public let kind: String
    public let latest: String?
    /// Sinds wanneer `latest` de nieuwste is; nil voor runtimes.
    public let since: Date?
    public let behind: [PackageUser]
    public let current: [PackageUser]

    public var state: State {
        guard latest != nil else { return .unchecked }
        return behind.isEmpty ? .current : .updateAvailable
    }
}

public enum PackageVersions {
    /// Alleen zoveel delen als `used` heeft: "1.27" loopt niet achter op "1.27.4".
    public static func isBehind(_ used: String, latest: String) -> Bool {
        let usedParts = used.split(separator: ".").map { Int($0) ?? 0 }
        let latestParts = latest.split(separator: ".").map { Int($0) ?? 0 }
        for i in usedParts.indices {
            let l = i < latestParts.count ? latestParts[i] : 0
            if usedParts[i] != l { return usedParts[i] < l }
        }
        return false
    }

    static func kind(ofEcosystem ecosystem: String) -> String {
        switch ecosystem {
        case "Go": "go"
        case "Packagist": "composer"
        case "NuGet": "nuget"
        case "PyPI": "pypi"
        case "crates.io": "cargo"
        case "SwiftURL": "swift"
        default: ecosystem
        }
    }
}

extension VersionReport {
    /// Alle packages en runtime-cycli over de repo's heen: eerst met een nieuwe versie (meeste repo's
    /// achter eerst), dan actueel, dan niet te checken; daarbinnen op naam. Frameworks
    /// (`StackDetector.lockedPackages`) staan alleen als library, met de versie uit het register.
    public func packageSummaries() -> [PackageSummary] {
        struct Group {
            var label: String
            var kind: String
            var latest: String?
            var since: Date?
            var users: [PackageUser] = []
        }
        var order: [String] = []
        var groups: [String: Group] = [:]
        func add(_ id: String, _ make: @autoclosure () -> Group, _ user: PackageUser) {
            if groups[id] == nil {
                order.append(id)
                groups[id] = make()
            }
            // Zelfde runtime twee keer in één repo (go.mod en Docker-image): één regel, oudste versie.
            if let index = groups[id]?.users.firstIndex(where: { $0.repoId == user.repoId }), let existing = groups[id]?.users[index] {
                groups[id]?.users[index] = PackageUser(
                    repoId: existing.repoId, repo: existing.repo,
                    version: VersionChecker.isOlder(user.version, than: existing.version) ? user.version : existing.version,
                    sources: existing.sources + user.sources.filter { !existing.sources.contains($0) }
                )
            } else {
                groups[id]?.users.append(user)
            }
        }
        for repo in repos where repo.error == nil {
            for component in repo.components where StackDetector.lockedPackages[component.product] == nil {
                guard let cycle = component.cycle, let latest = component.cycleLatest else { continue }
                add("runtime:\(component.product):\(cycle)",
                    Group(label: "\(component.label) \(cycle)", kind: "runtime", latest: latest),
                    PackageUser(repoId: repo.id, repo: repo.repo, version: component.version, sources: component.sources))
            }
            for package in repo.packages {
                let latest = latestPackages[package.key]
                add(package.key,
                    Group(label: package.name, kind: PackageVersions.kind(ofEcosystem: package.ecosystem),
                          latest: latest?.version, since: latest?.version == nil ? nil : latest?.seenAt),
                    PackageUser(repoId: repo.id, repo: repo.repo, version: package.version, sources: package.sources))
            }
        }
        let summaries = order.compactMap { id -> PackageSummary? in
            guard let group = groups[id] else { return nil }
            let behind = group.latest.map { latest in group.users.filter { PackageVersions.isBehind($0.version, latest: latest) } } ?? []
            return PackageSummary(
                id: id, label: group.label, kind: group.kind, latest: group.latest, since: group.since,
                behind: behind, current: group.users.filter { !behind.contains($0) }
            )
        }
        func rank(_ state: PackageSummary.State) -> Int {
            switch state {
            case .updateAvailable: 0
            case .current: 1
            case .unchecked: 2
            }
        }
        return summaries.sorted {
            if rank($0.state) != rank($1.state) { return rank($0.state) < rank($1.state) }
            if $0.behind.count != $1.behind.count { return $0.behind.count > $1.behind.count }
            return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }

    /// Behoudt `seenAt` uit `previous` zolang de nieuwste versie van een package niet veranderde.
    public func carryingSeenDates(from previous: VersionReport?) -> VersionReport {
        guard let previous else { return self }
        var latest = latestPackages
        for (key, value) in latest {
            if let old = previous.latestPackages[key], old.version == value.version {
                latest[key] = old
            }
        }
        return VersionReport(checkedAt: checkedAt, repos: repos, latestPackages: latest)
    }

    /// Packages en runtime-cycli waarvan de nieuwste versie veranderde sinds `previous` en waar een
    /// repo op achterloopt. Wat in `previous` nog geen bekende nieuwste versie had, telt niet: anders
    /// komt er bij de eerste check (of een nieuw package) een stortvloed aan meldingen.
    public func newPackageVersions(since previous: VersionReport?) -> [PackageSummary] {
        guard let previous else { return [] }
        let before = Dictionary(previous.packageSummaries().map { ($0.id, $0.latest) }, uniquingKeysWith: { first, _ in first })
        return packageSummaries().filter { summary in
            guard summary.state == .updateAvailable, let old = before[summary.id] ?? nil else { return false }
            return old != summary.latest
        }
    }
}
