import PullwatchCore
import SwiftUI

/// Welke groepen in Afhankelijkheden open staan: wat je kunt bijwerken, wat een manifest vraagt,
/// wat geblokkeerd is en kwetsbare packages die alleen transitief binnenkomen standaard wel, de
/// rest niet.
struct PackageSectionExpansion {
    private var expanded: Set<PackageSection.Kind> = [.canUpdateNow, .needsManifestChange, .blocked, .transitiveOnly]

    subscript(kind: PackageSection.Kind) -> Bool {
        get { expanded.contains(kind) }
        set {
            if newValue { expanded.insert(kind) } else { expanded.remove(kind) }
        }
    }
}

/// Een groep packages in de tabel: naar wat je met de nieuwe versie kunt, dan wat niet te checken is.
struct PackageSection: Identifiable {
    enum Kind: CaseIterable, Hashable {
        case canUpdateNow, needsManifestChange, blocked, transitiveOnly, unknown, upToDate, unchecked

        init(_ summary: PackageSummary) {
            guard !summary.isTransitiveOnly else {
                self = .transitiveOnly
                return
            }
            guard summary.state != .unchecked else {
                self = .unchecked
                return
            }
            switch summary.category {
            case .canUpdateNow: self = .canUpdateNow
            case .needsManifestChange: self = .needsManifestChange
            case .blocked: self = .blocked
            case .unknown: self = .unknown
            case .upToDate: self = .upToDate
            }
        }
    }

    let kind: Kind
    let packages: [PackageRow]

    var id: Kind { kind }

    var title: LocalizedStringResource {
        switch kind {
        case .canUpdateNow: UpdateCategory.canUpdateNow.title
        case .needsManifestChange: UpdateCategory.needsManifestChange.title
        case .blocked: UpdateCategory.blocked.title
        case .unknown: UpdateCategory.unknown.title
        case .upToDate: UpdateCategory.upToDate.title
        case .transitiveOnly: "Alleen transitief, met een kwetsbaarheid"
        case .unchecked: "Niet te checken"
        }
    }
}

/// Een package met de stip voor "nieuw sinds je vorige keer kijken".
struct PackageRow: Hashable, Identifiable {
    let summary: PackageSummary
    let isNew: Bool
    /// Het register van dit package staat uit; daarom is er geen nieuwste versie.
    var skippedSource: DataSourceID? = nil

    var id: String { summary.id }

    /// Wie achterloopt eerst, daarna wie al actueel is, dan wie het alleen transitief heeft.
    var users: [PackageUserRow] {
        // Zonder nieuwste versie is niemand "actueel".
        let current: PackageUserRow.Standing = summary.latest == nil ? .unchecked : .current
        return summary.behind.map { PackageUserRow(packageId: summary.id, user: $0, standing: .behind, latest: summary.latest) }
            + summary.current.map { PackageUserRow(packageId: summary.id, user: $0, standing: current, latest: summary.latest) }
            + summary.transitiveOnly.map { PackageUserRow(packageId: summary.id, user: $0, standing: .transitiveOnly, latest: summary.latest) }
    }
}

/// Eén repo die een package gebruikt, als rij onder dat package.
struct PackageUserRow: Hashable, Identifiable {
    enum Standing: Hashable {
        /// De oudste versie die de repo zelf vraagt is ouder dan de nieuwste.
        case behind
        case current
        /// Alleen via andere packages: de repo kan het niet zelf bijwerken.
        case transitiveOnly
        /// Geen nieuwste versie bekend: niet achter, maar ook niet actueel.
        case unchecked
    }

    let packageId: String
    let user: PackageUser
    let standing: Standing
    let latest: String?

    var id: String { "\(packageId)|\(user.repoId)" }

    /// De installs per workspace (root eerst) en daarbinnen direct eerst; de workspace alleen
    /// genoemd als de repo er meer dan één heeft.
    var installs: [PackageInstallRow] {
        let showsWorkspace = Set(user.installs.map(\.workspace)).count > 1
        let sorted = user.installs.sorted {
            if $0.workspace != $1.workspace { return $0.workspace.isEmpty || (!$1.workspace.isEmpty && $0.workspace < $1.workspace) }
            if ($0.scope == .direct) != ($1.scope == .direct) { return $0.scope == .direct }
            return $0.version < $1.version
        }
        return sorted.enumerated().map { index, install in
            PackageInstallRow(index: index, packageId: packageId, repoId: user.repoId, install: install,
                              showsWorkspace: showsWorkspace, latest: latest,
                              update: user.updates.first { $0.install == install })
        }
    }
}

/// Eén install (versie in een workspace, direct of via een ander package) onder een repo.
struct PackageInstallRow: Hashable, Identifiable {
    let index: Int
    let packageId: String
    let repoId: String
    let install: PackageInstall
    let showsWorkspace: Bool
    let latest: String?
    /// De update-status van deze install; nil zonder installs (runtimes).
    let update: InstallUpdate?

    var id: String { "\(index)|\(packageId)|\(repoId)" }

    /// Alleen een directe install kan de repo zelf bijwerken.
    var isBehind: Bool {
        guard install.scope != .transitive, let latest else { return false }
        return PackageVersions.isBehind(install.version, latest: latest)
    }
}

/// Een rij in de tabel: een package of een repo eronder.
enum PackageNode: Hashable, Identifiable {
    case package(PackageRow)
    case user(PackageUserRow)
    case install(PackageInstallRow)

    var id: String {
        switch self {
        case .package(let row): "package|\(row.id)"
        case .user(let row): "user|\(row.id)"
        case .install(let row): "install|\(row.id)"
        }
    }

    /// De repo van een geselecteerde repo- of install-rij, voor openen; de repo-id staat achteraan.
    static func repoId(in ids: Set<ID>) -> String? {
        guard ids.count == 1, let id = ids.first, id.hasPrefix("user|") || id.hasPrefix("install|") else { return nil }
        return id.split(separator: "|").last.map(String.init)
    }
}

extension PackageRow {
    /// De status van de repo die bepaalt in welke groep het package staat.
    var leadingStatus: UpdateStatus? {
        let category = summary.category
        return (summary.behind + summary.current)
            .first { $0.category(latest: summary.latest) == category }
            .map { UpdateStatus(user: $0, latest: summary.latest) }
    }
}
