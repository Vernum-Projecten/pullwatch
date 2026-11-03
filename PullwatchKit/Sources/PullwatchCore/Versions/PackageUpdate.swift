import Foundation

/// Of een install naar de nieuwste versie kan: uit wat de repo zelf zegt (de geïnstalleerde
/// versie, het gevraagde bereik in `PackageInstall.requested`) en uit wat de registers per versie
/// zeggen (`UpdateContext`): wat een ouder, een peer of de runtime tegenhoudt, en de nieuwste
/// versie die nu wel kan.
public struct PackageUpdate: Hashable, Sendable {
    public enum Status: Codable, Hashable, Sendable {
        /// De nieuwste versie is geïnstalleerd (of een nieuwere).
        case upToDate
        /// De nieuwste versie valt binnen het gevraagde bereik: alleen de lockfile verandert.
        case withinRange
        /// De nieuwste versie valt buiten het bereik in het manifest: dat moet mee.
        case needsManifestChange
        /// Een ander package houdt de nieuwste versie tegen: de ouder van een transitieve install
        /// met zijn bereik, of een package dat dit package als peer vraagt. Eerst `parent` bijwerken
        /// naar `minimumParentVersion` (nil als geen versie het toelaat of het niet bekend is).
        case blockedByPackage(parent: String, parentRange: String, minimumParentVersion: String?)
        /// De nieuwste versie vraagt een peer die de workspace in een andere versie heeft.
        case blockedByPeer(name: String, needs: String, installed: String)
        /// De nieuwste versie vraagt een nieuwere runtime dan de repo gebruikt.
        case blockedByRuntime(runtime: String, needs: String, installed: String)
        /// Geen nieuwste versie, of een versie of bereik dat niet te lezen is.
        case unknown

        init(_ blocker: UpdateBlocker) {
            switch blocker {
            case .package(let parent, let range, let minimum): self = .blockedByPackage(parent: parent, parentRange: range, minimumParentVersion: minimum)
            case .peer(let name, let needs, let installed): self = .blockedByPeer(name: name, needs: needs, installed: installed)
            case .runtime(let runtime, let needs, let installed): self = .blockedByRuntime(runtime: runtime, needs: needs, installed: installed)
            }
        }

        /// Wat de update tegenhoudt; nil als niets.
        public var blocker: UpdateBlocker? {
            switch self {
            case .blockedByPackage(let parent, let range, let minimum): .package(parent: parent, parentRange: range, minimumParentVersion: minimum)
            case .blockedByPeer(let name, let needs, let installed): .peer(name: name, needs: needs, installed: installed)
            case .blockedByRuntime(let runtime, let needs, let installed): .runtime(runtime: runtime, needs: needs, installed: installed)
            case .upToDate, .withinRange, .needsManifestChange, .unknown: nil
            }
        }

        /// Hoeveel werk: geblokkeerd, dan manifest, dan binnen bereik, dan onbekend.
        var weight: Int {
            switch self {
            case .blockedByPackage, .blockedByPeer, .blockedByRuntime: 4
            case .needsManifestChange: 3
            case .withinRange: 2
            case .unknown: 1
            case .upToDate: 0
            }
        }
    }

    public let status: Status
    /// Grootte van de stap naar `latest`; nil als er geen stap is of de versies niet te lezen zijn.
    public let step: UpdateStep?
    public let latest: String?
    /// De hoogste versie die elke eis haalt (ouder, peers, runtime), naast `latest`; de
    /// geïnstalleerde versie als geen nieuwere dat doet, nil zonder metadata uit het register.
    public let usable: String?

    public init(status: Status, step: UpdateStep?, latest: String?, usable: String? = nil) {
        self.status = status
        self.step = step
        self.latest = latest
        self.usable = usable
    }

    /// De status van één install van `name` in `ecosystem`, alleen uit het bereik.
    public init(ecosystem: String, name: String, installed: String, requested: String?, latest: String?) {
        self.init(
            ecosystem: ecosystem, name: name,
            install: PackageInstall(version: installed, workspace: "", scope: .direct, source: "", requested: requested),
            latest: latest, context: .empty
        )
    }

    /// De status van `install`, met de blokkades uit `context`.
    public init(ecosystem: String, name: String, install: PackageInstall, latest: String?, context: UpdateContext) {
        var needs = UpdateNeeds()
        self.init(ecosystem: ecosystem, name: name, install: install, latest: latest, context: context, needs: &needs)
    }

    init(ecosystem: String, name: String, install: PackageInstall, latest: String?, context: UpdateContext, needs: inout UpdateNeeds) {
        self.latest = latest
        guard let latest, let target = Version(latest), let current = Version(install.version) else {
            self.status = .unknown
            self.step = nil
            self.usable = nil
            return
        }
        self.step = UpdateStep(from: current, to: target)
        guard target > current else {
            self.status = .upToDate
            self.usable = context.metadata["\(ecosystem):\(name)"] == nil ? nil : install.version
            return
        }
        let check = context.check(ecosystem: ecosystem, name: name, install: install, target: target, findMinimum: true, needs: &needs)
        if case .blocked(let blocker) = check {
            self.status = Status(blocker)
        } else if let requested = install.requested, let range = VersionRange.parse(ecosystem: ecosystem, name: name, requested: requested) {
            self.status = range.contains(target) ? .withinRange : .needsManifestChange
        } else {
            self.status = .unknown
        }
        self.usable = check == .passes ? latest : context.newestUsable(ecosystem: ecosystem, name: name, install: install, needs: &needs)
    }

    /// Eén status voor meerdere installs: wat het meeste werk vraagt telt (geblokkeerd, manifest,
    /// binnen bereik, onbekend), met de grootste stap en de laagste bruikbare versie; zonder installs nil.
    public static func combined(_ updates: [PackageUpdate]) -> PackageUpdate? {
        guard let first = updates.first else { return nil }
        let status = updates.map(\.status).max { $0.weight < $1.weight } ?? first.status
        let usable = updates.compactMap(\.usable).min { VersionChecker.isOlder($0, than: $1) }
        return PackageUpdate(status: status, step: updates.compactMap(\.step).max(), latest: first.latest, usable: usable)
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
    public func update(ecosystem: String, name: String, latest: String?, context: UpdateContext = .empty) -> PackageUpdate {
        PackageUpdate(ecosystem: ecosystem, name: name, install: self, latest: latest, context: context)
    }
}

extension PackageUse {
    /// De status van elke install, op volgorde van `installs`.
    public func updates(latest: String?, context: UpdateContext = .empty) -> [InstallUpdate] {
        installs.map { InstallUpdate(install: $0, update: $0.update(ecosystem: ecosystem, name: name, latest: latest, context: context)) }
    }

    /// Eén status voor wat de repo zelf kan bijwerken (`directInstalls`).
    public func update(latest: String?, context: UpdateContext = .empty) -> PackageUpdate? {
        PackageUpdate.combined(directInstalls.map { $0.update(ecosystem: ecosystem, name: name, latest: latest, context: context) })
    }
}
