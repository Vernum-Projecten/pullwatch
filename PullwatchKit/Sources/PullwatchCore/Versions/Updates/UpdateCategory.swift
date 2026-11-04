import Foundation

/// Wat je met een nieuwere versie kunt, als groep in Afhankelijkheden: nu bijwerken, eerst het
/// manifest aanpassen, eerst iets anders bijwerken, niet te zeggen, of niets te doen. De volgorde
/// is die van de groepen: wat je nu kunt eerst.
public enum UpdateCategory: Int, CaseIterable, Hashable, Sendable, Comparable {
    /// Binnen het gevraagde bereik (alleen de lockfile verandert), of een runtime binnen zijn cyclus.
    case canUpdateNow
    /// Buiten het bereik in het manifest, meestal een major.
    case needsManifestChange
    /// Een ouder, peer of runtime houdt de nieuwe versie tegen.
    case blocked
    /// Er is een nieuwere versie, maar bereik of versie is niet te lezen.
    case unknown
    case upToDate

    public static func < (lhs: UpdateCategory, rhs: UpdateCategory) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension PackageUpdate.Status {
    public var category: UpdateCategory {
        switch self {
        case .upToDate: .upToDate
        case .withinRange: .canUpdateNow
        case .needsManifestChange: .needsManifestChange
        case .blockedByPackage, .blockedByPeer, .blockedByRuntime: .blocked
        case .unknown: .unknown
        }
    }
}

extension PackageUser {
    /// De groep van deze repo voor een package met `latest` als nieuwste: actueel als de repo niet
    /// achterloopt, anders de status van wat de repo zelf kan bijwerken. Een runtime (zonder
    /// installs) die achterloopt, kan binnen zijn cyclus nu bij.
    public func category(latest: String?) -> UpdateCategory {
        guard let latest, PackageVersions.isBehind(version, latest: latest) || isTransitiveOnly else { return .upToDate }
        guard let update else { return .canUpdateNow }
        return update.status.category
    }
}

extension PackageSummary {
    /// De groep van het package: wat in een repo die het zelf vraagt het meest mogelijk is (nu
    /// bijwerken gaat voor manifest, dat voor geblokkeerd). Repo's die het alleen transitief
    /// hebben tellen niet mee; zonder nieuwste versie `unknown`.
    public var category: UpdateCategory {
        guard latest != nil else { return .unknown }
        return (behind + current).map { $0.category(latest: latest) }.min() ?? .upToDate
    }

    /// Repo's die het package zelf vragen en nu binnen hun bereik kunnen bijwerken.
    public var canUpdateNowCount: Int {
        (behind + current).filter { $0.category(latest: latest) == .canUpdateNow }.count
    }
}

extension PackageVersions {
    /// Wat de badge van Afhankelijkheden telt: nog niet geziene nieuwe versies die je nu kunt
    /// nemen, en die met een oplossing voor een kwetsbaarheid (`securityFixes`, `PackageUse.key`).
    public static func badgeCount(_ summaries: [PackageSummary], seen: [String: String], securityFixes: Set<String>) -> Int {
        unseen(summaries, seen: seen).filter { $0.category == .canUpdateNow || securityFixes.contains($0.id) }.count
    }
}

extension VersionReport {
    /// `PackageUse.key` van elk package met een kwetsbaarheid waarvoor een oplossing bestaat.
    public var packagesWithSecurityFixes: Set<String> {
        Set(repos.filter { $0.error == nil }.flatMap { repo in
            repo.vulnerabilities.filter { $0.fixedIn != nil }.map { "\($0.ecosystem):\($0.package)" }
        })
    }

    /// Als `newPackageVersions(since:)`, met `onlyCanUpdateNow` alleen de packages die een repo nu
    /// binnen zijn bereik kan bijwerken.
    public func newPackageVersions(since previous: VersionReport?, onlyCanUpdateNow: Bool) -> [PackageSummary] {
        let new = newPackageVersions(since: previous)
        return onlyCanUpdateNow ? new.filter { $0.category == .canUpdateNow } : new
    }
}
