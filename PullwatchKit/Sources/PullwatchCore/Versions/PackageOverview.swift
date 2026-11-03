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

    /// Oude waarde houden bij dezelfde versie of als de nieuwe opzoeking mislukte.
    static func keepsOld(_ old: PackageLatest, over new: PackageLatest) -> Bool {
        old.version == new.version || new.version == nil
    }
}

/// Eén repo die een package of runtime-cyclus gebruikt.
public struct PackageUser: Hashable, Sendable, Identifiable {
    public let repoId: String
    public let repo: String
    /// Oudste direct gebruikte versie: daarop wordt "loopt achter" beoordeeld.
    public let version: String
    public let sources: [String]
    /// Elke install van het package in deze repo (versie, workspace, scope, soort, via); leeg voor runtimes.
    public let installs: [PackageInstall]

    public init(repoId: String, repo: String, version: String, sources: [String], installs: [PackageInstall] = []) {
        self.repoId = repoId
        self.repo = repo
        self.version = version
        self.sources = sources
        self.installs = installs
    }

    public var id: String { repoId }

    /// Alle versies van het package in deze repo, oudste eerst; voor runtimes alleen `version`.
    public var versions: [String] {
        guard !installs.isEmpty else { return [version] }
        return PackageUse(ecosystem: "", name: "", installs: installs).versions
    }
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
    /// Repo's die het package alleen transitief hebben: niet zelf bij te werken, dus nooit "achter".
    public let transitiveOnly: [PackageUser]

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

    /// Updates waarvan de nieuwste versie nog niet gezien is; `seen` is id → laatst geziene `latest`.
    public static func unseen(_ summaries: [PackageSummary], seen: [String: String]) -> [PackageSummary] {
        summaries.filter { $0.state == .updateAvailable && seen[$0.id] != $0.latest }
    }

    static func kind(ofEcosystem ecosystem: String) -> String {
        switch ecosystem {
        case "Go": "go"
        case "Packagist": "composer"
        case "NuGet": "nuget"
        case "PyPI": "pypi"
        case "crates.io": "cargo"
        case "RubyGems": "gem"
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
                    sources: existing.sources + user.sources.filter { !existing.sources.contains($0) },
                    installs: existing.installs + user.installs.filter { !existing.installs.contains($0) }
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
                    PackageUser(repoId: repo.id, repo: repo.repo, version: package.version, sources: package.sources, installs: package.installs))
            }
        }
        // Repo's die een package dat elders direct gebruikt wordt alleen transitief hebben; een
        // package dat nergens direct gebruikt wordt krijgt geen eigen regel.
        for repo in repos where repo.error == nil {
            for package in repo.otherPackages where groups[package.key] != nil {
                let user = PackageUser(repoId: repo.id, repo: repo.repo, version: package.version, sources: package.sources, installs: package.installs)
                if user.isTransitiveOnly, groups[package.key]?.users.contains(where: { $0.repoId == repo.id }) == false {
                    groups[package.key]?.users.append(user)
                }
            }
        }
        let summaries = order.compactMap { id -> PackageSummary? in
            guard let group = groups[id] else { return nil }
            let transitiveOnly = group.users.filter(\.isTransitiveOnly)
            let own = group.users.filter { !$0.isTransitiveOnly }
            let behind = group.latest.map { latest in own.filter { PackageVersions.isBehind($0.version, latest: latest) } } ?? []
            return PackageSummary(
                id: id, label: group.label, kind: group.kind, latest: group.latest, since: group.since,
                behind: behind, current: own.filter { !behind.contains($0) }, transitiveOnly: transitiveOnly
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

    /// Behoudt `seenAt` uit `previous` zolang de nieuwste versie van een package niet veranderde. Een
    /// mislukte opzoeking (nil) wist een eerder bekende versie niet: anders mist de volgende check de melding.
    public func carryingSeenDates(from previous: VersionReport?) -> VersionReport {
        guard let previous else { return self }
        var latest = latestPackages
        for (key, value) in latest {
            if let old = previous.latestPackages[key], PackageLatest.keepsOld(old, over: value) {
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
