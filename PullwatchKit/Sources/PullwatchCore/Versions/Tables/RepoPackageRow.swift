import Foundation

/// Eén package in één workspace als rij in de tabel: de versies, de nieuwste die nu kan, de
/// nieuwste, en wat je ermee kunt. Alles wordt één keer berekend bij het opbouwen.
public struct RepoPackageRow: Hashable, Sendable, Identifiable {
    public let package: WorkspacePackage
    public let workspace: String
    public let origin: DependencyOrigin
    /// nil als het register geen nieuwste versie gaf.
    public let latest: String?
    /// Elke install met zijn status, op volgorde van `package.installs`; leeg zonder `latest`.
    public let installs: [InstallUpdate]
    /// Eén status voor wat de repo zelf kan bijwerken (de directe installs, anders alle); nil zonder `latest`.
    public let update: PackageUpdate?
    /// Geïnstalleerde versies, oudste eerst, elk één keer.
    public let installedVersions: [String]
    /// De nieuwste versie die nu kan, als die anders is dan de nieuwste en nieuwer dan wat er staat.
    public let newestUsable: String?
    /// Alles waarop gezocht wordt, in één tekst.
    let searchable: String

    // Sorteersleutels voor de kolommen.
    public let nameSortKey: TextSortKey
    public let installedSortKey: VersionSortKey
    public let usableSortKey: VersionSortKey
    public let latestSortKey: VersionSortKey

    public init(package: WorkspacePackage, workspace: String, origin: DependencyOrigin, latest: String?, context: UpdateContext = .empty) {
        self.package = package
        self.workspace = workspace
        self.origin = origin
        self.latest = latest
        if latest != nil {
            let installs = package.installs.map {
                InstallUpdate(install: $0, update: $0.update(ecosystem: package.ecosystem, name: package.name, latest: latest, context: context))
            }
            self.installs = installs
            let direct = installs.filter { $0.install.scope == .direct }
            self.update = PackageUpdate.combined((direct.isEmpty ? installs : direct).map(\.update))
        } else {
            self.installs = []
            self.update = nil
        }
        let versions = package.installs.map(\.version).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .sorted { VersionChecker.isOlder($0, than: $1) }
        installedVersions = versions
        if let usable = update?.usable, usable != latest, !versions.contains(usable) {
            newestUsable = usable
        } else {
            newestUsable = nil
        }
        searchable = ([package.name, workspace] + versions + package.installs.flatMap(\.via)).joined(separator: "\n")
        nameSortKey = TextSortKey(package.name)
        installedSortKey = VersionSortKey(versions.first)
        usableSortKey = VersionSortKey(newestUsable)
        latestSortKey = VersionSortKey(latest)
    }

    public var id: String { "\(workspace)|\(package.id)" }
    public var name: String { package.name }

    /// Wat je met de nieuwste versie kunt; nil als die niet bekend is.
    public var category: UpdateCategory? { update?.status.category }

    /// De install die de status bepaalt: direct eerst.
    public var leading: InstallUpdate? {
        guard let update else { return nil }
        return installs.first { $0.install.scope == .direct && $0.update.status == update.status }
            ?? installs.first { $0.update.status == update.status }
    }

    /// Of er iets bij te werken is.
    public var hasUpdate: Bool { category.map { $0 != .upToDate } ?? false }

    /// Wat je nu kunt eerst, onbekend achteraan.
    public var statusSortKey: Int { category?.rawValue ?? UpdateCategory.allCases.count }
}

/// Een rij in de tabel van packages: een package, of één install eronder als het package in
/// deze workspace meer versies of ketens heeft.
public struct RepoPackageTableRow: Hashable, Sendable, Identifiable {
    public let row: RepoPackageRow
    /// nil voor de rij van het package zelf.
    public let install: PackageInstall?

    public init(row: RepoPackageRow, install: PackageInstall? = nil) {
        self.row = row
        self.install = install
    }

    public var id: String {
        guard let install else { return row.id }
        return "\(row.id)#\(install.version)|\(install.via.joined(separator: ">"))|\(install.source)"
    }

    /// De status van deze install; voor de rij van het package die van het package.
    public var update: InstallUpdate? {
        guard let install else { return row.leading }
        return row.installs.first { $0.install == install }
    }

    public var children: [RepoPackageTableRow] {
        guard install == nil, row.package.installs.count > 1 else { return [] }
        return row.package.installs.map { RepoPackageTableRow(row: row, install: $0) }
    }

    public var nameSortKey: TextSortKey { row.nameSortKey }
    public var installedSortKey: VersionSortKey { install.map { VersionSortKey($0.version) } ?? row.installedSortKey }
    public var usableSortKey: VersionSortKey { row.usableSortKey }
    public var latestSortKey: VersionSortKey { row.latestSortKey }
    public var statusSortKey: Int { row.statusSortKey }
}

/// Wat de tabel van packages toont: herkomst, status en een zoekterm.
public struct PackageFilter: Hashable, Sendable {
    /// Wat een package toont op status.
    public enum Status: Hashable, Sendable {
        /// Elke nieuwere versie, wat er ook mee kan.
        case hasUpdate
        case category(UpdateCategory)
    }

    /// Leeg is elke herkomst.
    public var origins: Set<DependencyOrigin> = []
    /// nil is elke status.
    public var status: Status?

    public init(origins: Set<DependencyOrigin> = [], status: Status? = nil) {
        self.origins = origins
        self.status = status
    }

    public var isActive: Bool { !origins.isEmpty || status != nil }

    public func matches(_ row: RepoPackageRow, text: String = "") -> Bool {
        if !origins.isEmpty && !origins.contains(row.origin) { return false }
        switch status {
        case .hasUpdate?: if !row.hasUpdate { return false }
        case .category(let category)?: if row.category != category { return false }
        case nil: break
        }
        let query = text.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || row.searchable.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

/// De packages van één workspace in de tabel.
public struct RepoPackageGroup: Hashable, Sendable, Identifiable {
    public let workspace: String
    public let rows: [RepoPackageRow]

    public init(workspace: String, rows: [RepoPackageRow]) {
        self.workspace = workspace
        self.rows = rows
    }

    public var id: String { workspace }
}

extension RepoVersions {
    /// Elk package per workspace (de root eerst) als rij, met `latest` (op `PackageUse.key`) en
    /// de blokkades uit `context`.
    public func packageGroups(latest: (String) -> String?, context: UpdateContext = .empty) -> [RepoPackageGroup] {
        packageWorkspaces.filter { !$0.isEmpty }.map { workspace in
            let rows = [
                (DependencyOrigin.direct, workspace.direct), (.transitive, workspace.transitive),
                (.unknown, workspace.unknown), (.dev, workspace.dev),
            ].flatMap { origin, packages in
                packages.map { RepoPackageRow(package: $0, workspace: workspace.workspace, origin: origin, latest: latest($0.id), context: context) }
            }
            return RepoPackageGroup(workspace: workspace.workspace, rows: rows)
        }
    }
}
