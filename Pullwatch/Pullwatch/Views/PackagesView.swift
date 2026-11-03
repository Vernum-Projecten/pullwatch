import PullwatchCore
import SwiftUI

/// Versies per package over alle gevolgde repo's, in een tabel: per package de repo's die het
/// gebruiken als uitklapbare rijen; dubbelklik op een repo opent de pagina ervan.
struct PackagesView: View {
    let model: AppModel

    @State private var searchText = ""
    @State private var selection: PackageNode.ID?
    @State private var expansion = PackageSectionExpansion()
    /// Wat bij openen als gezien gemarkeerd werd; die rijen krijgen geen stip meer. Vastgelegd bij
    /// openen, zodat de stippen zichtbaar blijven zolang je kijkt.
    @State private var seenAtOpen: [String: String] = [:]
    @State private var sections: [PackageSection] = []
    /// Opengeklapte package- en repo-rijen.
    @State private var expandedRows: Set<PackageNode.ID> = []

    private func isExpanded(_ node: PackageNode) -> Binding<Bool> {
        Binding(
            get: { expandedRows.contains(node.id) },
            set: { open in
                if open { expandedRows.insert(node.id) } else { expandedRows.remove(node.id) }
            }
        )
    }

    private struct Query: Equatable {
        let text: String
        let summaries: [PackageSummary]
        let seen: [String: String]
        let disabled: Set<DataSourceID>
    }

    private func recompute() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let found = model.packageSummaries.filter { summary in
            query.isEmpty
                || summary.label.localizedCaseInsensitiveContains(query)
                || (summary.behind + summary.current + summary.transitiveOnly).contains { $0.repo.localizedCaseInsensitiveContains(query) }
        }
        sections = PackageSection.Kind.allCases.compactMap { kind in
            let summaries = found.filter { kind.state == $0.state }
            guard !summaries.isEmpty else { return nil }
            return PackageSection(kind: kind, packages: summaries.map { summary in
                PackageRow(
                    summary: summary,
                    isNew: summary.state == .updateAvailable && seenAtOpen[summary.id] != summary.latest,
                    skippedSource: summary.state == .unchecked
                        ? SourceOff.registry(ofPackage: summary.id, in: model.config.disabledSources) : nil
                )
            })
        }
        #if DEBUG
        if SnapshotCamera.expandsAll {
            for row in sections.flatMap(\.packages) {
                expandedRows.insert(PackageNode.package(row).id)
                for user in row.users { expandedRows.insert(PackageNode.user(user).id) }
            }
        }
        #endif
    }

    var body: some View {
        Table(of: PackageNode.self, selection: $selection) {
            TableColumn("Package") { node in
                PackageNameCell(node: node)
            }
            .width(min: 180, ideal: 260)
            TableColumn("Versie") { node in
                PackageVersionCell(node: node)
            }
            .width(min: 90, ideal: 120)
            TableColumn("Stand") { node in
                PackageStatusCell(node: node)
            }
            .width(min: 140, ideal: 220)
            TableColumn("Sinds") { node in
                if case .package(let row) = node, row.summary.state == .updateAvailable, let since = row.summary.since {
                    Text(since, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                        .help(Text("Sinds wanneer deze versie de nieuwste is"))
                }
            }
            .width(min: 80, ideal: 110)
        } rows: {
            ForEach(sections) { section in
                Section(isExpanded: $expansion[section.kind]) {
                    ForEach(section.packages) { row in
                        DisclosureTableRow(PackageNode.package(row), isExpanded: isExpanded(.package(row))) {
                            ForEach(row.users) { user in
                                // Meer installs (workspaces, versies): elk een eigen rij onder de repo.
                                if user.installs.count > 1 {
                                    DisclosureTableRow(PackageNode.user(user), isExpanded: isExpanded(.user(user))) {
                                        ForEach(user.installs) { install in
                                            TableRow(PackageNode.install(install))
                                        }
                                    }
                                } else {
                                    TableRow(PackageNode.user(user))
                                }
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 4) {
                        Text(section.title)
                        Text(verbatim: "(\(section.packages.count))")
                    }
                }
            }
        }
        .contextMenu(forSelectionType: PackageNode.ID.self) { ids in
            if let repoId = PackageNode.repoId(in: ids) {
                Button("Open de pagina van deze repo") { model.showRepo(id: repoId) }
            }
        } primaryAction: { ids in
            if let repoId = PackageNode.repoId(in: ids) { model.showRepo(id: repoId) }
        }
        .overlay {
            if model.versionReport == nil && model.versionCheck != nil {
                // De voortgang staat in de balk onderin; hier alleen wat er gebeurt.
                ContentUnavailableView(
                    "Afhankelijkheden checken…",
                    systemImage: "shippingbox",
                    description: Text("Pullwatch leest de runtimes en packages van de repo's die je volgt.")
                )
            } else if model.versionReport == nil {
                ContentUnavailableView(
                    "Nog niet gecheckt",
                    systemImage: "shippingbox",
                    description: Text("Zie welke runtimes en packages je repo's gebruiken en of er een nieuwere versie is.")
                )
            } else if sections.isEmpty {
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView(
                        "Geen packages gevonden",
                        systemImage: "shippingbox",
                        description: Text("Check opnieuw om ook de packages van je repo's op te halen.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .searchable(text: $searchText, prompt: Text("Zoek op package of repo…"))
        .searchShortcut()
        .navigationTitle(Text("Afhankelijkheden"))
        .navigationSubtitle(CheckedSubtitle.text(model.versionReport?.checkedAt))
        .toolbar {
            CheckAllToolbarItem(model: model)
        }
        .onAppear {
            seenAtOpen = model.seenPackageVersions
            model.markPackagesSeen()
        }
        .onChange(of: model.packagesSearch, initial: true) { _, search in
            guard let search else { return }
            searchText = search
            model.packagesSearch = nil
        }
        .onChange(of: model.versionReport?.checkedAt) {
            // Nieuwe check terwijl je kijkt: wat nu nieuw is houdt zijn stip tot je terugkomt.
            model.markPackagesSeen()
        }
        .onChange(
            of: Query(text: searchText, summaries: model.packageSummaries, seen: seenAtOpen, disabled: model.config.disabledSources),
            initial: true
        ) {
            recompute()
        }
    }
}

/// Welke groepen in Afhankelijkheden open staan; "Nieuwe versie beschikbaar" standaard wel, de rest niet.
struct PackageSectionExpansion {
    private var expanded: Set<PackageSection.Kind> = [.updates]

    subscript(kind: PackageSection.Kind) -> Bool {
        get { expanded.contains(kind) }
        set {
            if newValue { expanded.insert(kind) } else { expanded.remove(kind) }
        }
    }
}

/// Een groep packages in de tabel.
struct PackageSection: Identifiable {
    enum Kind: CaseIterable, Hashable {
        case updates, current, unchecked

        var state: PackageSummary.State {
            switch self {
            case .updates: .updateAvailable
            case .current: .current
            case .unchecked: .unchecked
            }
        }
    }

    let kind: Kind
    let packages: [PackageRow]

    var id: Kind { kind }

    var title: LocalizedStringResource {
        switch kind {
        case .updates: "Nieuwe versie beschikbaar"
        case .current: "Actueel"
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
                              showsWorkspace: showsWorkspace, latest: latest)
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

private struct PackageNameCell: View {
    let node: PackageNode

    var body: some View {
        switch node {
        case .package(let row):
            HStack(spacing: 6) {
                Circle()
                    .fill(row.isNew ? Color.accentColor : .clear)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(Text("Nieuw"))
                    .accessibilityHidden(!row.isNew)
                Text(verbatim: row.summary.label).fontWeight(.semibold).lineLimit(1)
                Text(verbatim: row.summary.kind).font(.caption).foregroundStyle(.secondary)
            }
        case .user(let row):
            HStack(spacing: 6) {
                Text(verbatim: row.user.repo).lineLimit(1)
                if row.standing == .transitiveOnly {
                    Pill(text: "Alleen transitief", tint: .secondary)
                        .help(Text("Deze repo vraagt het package niet zelf; het komt binnen via andere packages"))
                }
            }
            .help(Text("Dubbelklik om de pagina van deze repo te openen"))
        case .install(let row):
            Label(Workspace.name(row.install.workspace), systemImage: "folder")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(Text(verbatim: row.install.source))
        }
    }
}

private struct PackageVersionCell: View {
    let node: PackageNode

    var body: some View {
        switch node {
        case .package(let row):
            Text(verbatim: row.summary.latest ?? "").monospacedDigit()
                .foregroundStyle(row.summary.state == .updateAvailable ? .green : .secondary)
        case .user(let row):
            VersionLabel(version: row.user.version, standing: row.standing)
        case .install(let row):
            VersionLabel(
                version: row.install.version,
                standing: row.install.scope == .transitive ? .transitiveOnly
                    : row.isBehind ? .behind : row.latest == nil ? .unchecked : .current
            )
        }
    }
}

/// Een versie met een teken voor achter, actueel of alleen transitief.
private struct VersionLabel: View {
    let version: String
    let standing: PackageUserRow.Standing

    var body: some View {
        Label {
            Text(verbatim: version).monospacedDigit()
        } icon: {
            switch standing {
            case .behind: Image(systemName: "arrow.down.circle").foregroundStyle(.orange)
            case .current: Image(systemName: "checkmark.circle").foregroundStyle(.green)
            case .transitiveOnly: Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary)
            case .unchecked: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: Text {
        switch standing {
        case .behind: Text("\(version), loopt achter")
        case .current: Text("\(version), actueel")
        case .transitiveOnly: Text("\(version), alleen transitief")
        case .unchecked: Text("\(version), niet gecontroleerd")
        }
    }
}

private struct PackageStatusCell: View {
    let node: PackageNode

    var body: some View {
        switch node {
        case .package(let row):
            switch row.summary.state {
            case .updateAvailable:
                Text("\(row.summary.behind.count) repo's lopen achter").foregroundStyle(.orange)
            case .current:
                Text("gebruikt in \(row.summary.current.count) repo's").foregroundStyle(.secondary)
            case .unchecked:
                if let source = row.skippedSource {
                    Text(verbatim: SourceOff.versionNotChecked(source)).foregroundStyle(.secondary).lineLimit(1)
                        .help(Text(verbatim: SourceOff.versionNotChecked(source)))
                } else {
                    Text("Nieuwste versie niet op te halen").foregroundStyle(.secondary)
                }
            }
        case .user(let row):
            if row.user.installs.count > 1 {
                // Meer versies: hoeveel; één versie op meer plekken: welke workspaces.
                Group {
                    if row.user.versions.count > 1 {
                        Text("\(row.user.versions.count) versies", comment: "Aantal verschillende versies van een package in deze repo")
                            .foregroundStyle(.orange)
                    } else {
                        Text(verbatim: row.user.installs.map { Workspace.name($0.workspace) }
                            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                            .joined(separator: ", "))
                        .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            } else if let install = row.user.installs.first {
                ProvenanceCell(install: install, showsWorkspace: !install.workspace.isEmpty)
            } else {
                Text(verbatim: row.user.sources.joined(separator: ", "))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help(row.user.sources.joined(separator: "\n"))
            }
        case .install(let row):
            ProvenanceCell(install: row.install, showsWorkspace: false)
        }
    }
}

/// "Direct", "via express → body-parser" (voorgelezen als "via express, dan body-parser"), met
/// de workspace en "Dev" erbij.
private struct ProvenanceCell: View {
    let install: PackageInstall
    let showsWorkspace: Bool

    var body: some View {
        InstallLine(
            workspace: showsWorkspace ? install.workspace : nil,
            scope: install.scope,
            via: install.via,
            isDev: install.kind == .dev,
            font: .body
        )
        .help(Text(verbatim: install.source))
    }
}
