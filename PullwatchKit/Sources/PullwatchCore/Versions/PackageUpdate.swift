import Foundation

/// Of een install naar de nieuwste versie kan, alleen uit wat de repo zelf zegt: de geïnstalleerde
/// versie, het gevraagde bereik (`PackageInstall.requested`) en `PackageRegistry.latest`. Wat een
/// update blokkeert (ouders, peers, runtimes) volgt later (#84).
public struct PackageUpdate: Hashable, Sendable {
    public enum Status: String, Codable, Hashable, Sendable {
        /// De nieuwste versie is geïnstalleerd (of een nieuwere).
        case upToDate
        /// De nieuwste versie valt binnen het gevraagde bereik: alleen de lockfile verandert.
        case withinRange
        /// De nieuwste versie valt buiten het bereik: het manifest moet mee (of, voor een
        /// transitieve install, het bereik van de ouder).
        case needsManifestChange
        /// Geen nieuwste versie, of een versie of bereik dat niet te lezen is.
        case unknown
    }

    public let status: Status
    /// Grootte van de stap naar `latest`; nil als er geen stap is of de versies niet te lezen zijn.
    public let step: UpdateStep?
    public let latest: String?

    public init(status: Status, step: UpdateStep?, latest: String?) {
        self.status = status
        self.step = step
        self.latest = latest
    }

    /// De status van één install van `name` in `ecosystem`.
    public init(ecosystem: String, name: String, installed: String, requested: String?, latest: String?) {
        self.latest = latest
        guard let latest, let target = Version(latest), let current = Version(installed) else {
            self.status = .unknown
            self.step = nil
            return
        }
        self.step = UpdateStep(from: current, to: target)
        if target <= current {
            self.status = .upToDate
        } else if let requested, let range = VersionRange.parse(ecosystem: ecosystem, name: name, requested: requested) {
            self.status = range.contains(target) ? .withinRange : .needsManifestChange
        } else {
            self.status = .unknown
        }
    }

    /// Eén status voor meerdere installs: wat het meeste werk vraagt telt (manifest, dan binnen
    /// bereik, dan onbekend), met de grootste stap; zonder installs nil.
    public static func combined(_ updates: [PackageUpdate]) -> PackageUpdate? {
        guard let first = updates.first else { return nil }
        func weight(_ status: Status) -> Int {
            switch status {
            case .needsManifestChange: 3
            case .withinRange: 2
            case .unknown: 1
            case .upToDate: 0
            }
        }
        let status = updates.map(\.status).max { weight($0) < weight($1) } ?? first.status
        return PackageUpdate(status: status, step: updates.compactMap(\.step).max(), latest: first.latest)
    }
}

/// Een install met zijn update-status.
public struct InstallUpdate: Hashable, Sendable {
    public let install: PackageInstall
    public let update: PackageUpdate

    public init(install: PackageInstall, update: PackageUpdate) {
        self.install = install
        self.update = update
    }
}

extension PackageInstall {
    public func update(ecosystem: String, name: String, latest: String?) -> PackageUpdate {
        PackageUpdate(ecosystem: ecosystem, name: name, installed: version, requested: requested, latest: latest)
    }
}

extension PackageUse {
    /// De status van elke install, op volgorde van `installs`.
    public func updates(latest: String?) -> [InstallUpdate] {
        installs.map { InstallUpdate(install: $0, update: $0.update(ecosystem: ecosystem, name: name, latest: latest)) }
    }

    /// Eén status voor wat de repo zelf kan bijwerken (`directInstalls`).
    public func update(latest: String?) -> PackageUpdate? {
        PackageUpdate.combined(directInstalls.map { $0.update(ecosystem: ecosystem, name: name, latest: latest) })
    }
}
