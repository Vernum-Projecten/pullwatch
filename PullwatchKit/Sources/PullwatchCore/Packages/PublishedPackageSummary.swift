public import Foundation

/// Een gevolgde repository die een eigen package gebruikt, met de versies die hij heeft.
public struct PublishedPackageUser: Hashable, Sendable, Identifiable {
    /// `RepoVersions.id` (en `RepoSummary.id`).
    public var id: String { repoId }
    public let repoId: String
    public let accountId: UUID
    public let repo: String
    /// De geïnstalleerde versies, oudste eerst, zonder dubbele.
    public let versions: [String]
    /// Of de repo het package zelf vraagt; anders komt het alleen via andere packages binnen.
    public let isDirect: Bool

    public init(repoId: String, accountId: UUID, repo: String, versions: [String], isDirect: Bool) {
        self.repoId = repoId
        self.accountId = accountId
        self.repo = repo
        self.versions = versions
        self.isDirect = isDirect
    }

    /// De oudste versie: wat de repo zelf kan bijwerken.
    public var version: String { versions.first ?? "" }
}

/// Eén rij van de Packages-sectie: een gepubliceerd package met de gevolgde repo's die het
/// gebruiken. Wie het gebruikt komt uit de check op eigen packages (`PackageMetadata.inHouse`):
/// een soort die die check niet herkent (container-images, Helm) heeft nooit gebruikers.
public struct PublishedPackageSummary: Hashable, Sendable, Identifiable {
    /// Uniek over de accounts heen.
    public var id: String { "\(package.accountId.uuidString)/\(package.id)" }
    public let package: PublishedPackage
    /// Op naam van de repo.
    public let users: [PublishedPackageUser]

    public init(package: PublishedPackage, users: [PublishedPackageUser]) {
        self.package = package
        self.users = users
    }

    /// Of de dependency-check dit soort package kan herkennen, zodat "gebruikt door" iets zegt.
    public var isMatchable: Bool { package.type.dependencyEcosystem != nil }
}

extension VersionReport {
    /// Elk gepubliceerd package met wie het gebruikt, op eigenaar en naam.
    public func publishedPackageSummaries() -> [PublishedPackageSummary] {
        let users = publishedPackageUsers()
        return allPublishedPackages
            .map { PublishedPackageSummary(package: $0, users: users[Self.usageKey($0)] ?? []) }
            .sorted { ($0.package.owner.lowercased(), $0.package.name.lowercased()) < ($1.package.owner.lowercased(), $1.package.name.lowercased()) }
    }

    /// Packages waarvan de nieuwste versie sinds `previous` veranderde. Een package dat er de vorige
    /// keer nog niet was telt niet (een eerste check of een account erbij geeft geen stapel
    /// meldingen), net als een account waarvan het register de vorige keer niets zei.
    public func newPublishedVersions(since previous: VersionReport?) -> [PublishedPackage] {
        guard let previous else { return [] }
        var before: [String: String] = [:]
        for package in previous.allPublishedPackages {
            if let latest = package.latestVersion { before["\(package.accountId.uuidString)/\(package.id)"] = latest }
        }
        return allPublishedPackages.filter { package in
            guard let latest = package.latestVersion, let old = before["\(package.accountId.uuidString)/\(package.id)"] else { return false }
            return old != latest
        }
    }

    /// Per eigen package (`usageKey`) de repo's met een dependency die de check als dat package herkende.
    private func publishedPackageUsers() -> [String: [PublishedPackageUser]] {
        var result: [String: [PublishedPackageUser]] = [:]
        for repo in repos {
            var found: [String: (versions: [String], isDirect: Bool)] = [:]
            for (uses, isDirect) in [(repo.packages, true), (repo.otherPackages, false)] {
                for use in uses {
                    guard let own = packageMetadata[use.key]?.inHouse else { continue }
                    let key = Self.usageKey(accountId: own.accountId, type: own.type, owner: own.owner, name: own.name)
                    var entry = found[key] ?? ([], false)
                    for version in use.installs.map(\.version) where !entry.versions.contains(version) {
                        entry.versions.append(version)
                    }
                    entry.isDirect = entry.isDirect || isDirect
                    found[key] = entry
                }
            }
            for (key, entry) in found {
                let versions = entry.versions.sorted { VersionChecker.isOlder($0, than: $1) }
                result[key, default: []].append(
                    PublishedPackageUser(repoId: repo.id, accountId: repo.accountId, repo: repo.repo, versions: versions, isDirect: entry.isDirect)
                )
            }
        }
        return result.mapValues { $0.sorted { $0.repo.lowercased() < $1.repo.lowercased() } }
    }

    private static func usageKey(_ package: PublishedPackage) -> String {
        usageKey(accountId: package.accountId, type: package.type, owner: package.owner, name: package.name)
    }

    private static func usageKey(accountId: UUID, type: PublishedPackageType, owner: String, name: String) -> String {
        "\(accountId.uuidString)/\(type.rawValue)/\(owner.lowercased())/\(name)"
    }
}
