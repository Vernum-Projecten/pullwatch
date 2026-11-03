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

    private struct Query: Equatable {
        let text: String
        let summaries: [PackageSummary]
        let seen: [String: String]
    }

    private func recompute() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let found = model.packageSummaries.filter { summary in
            query.isEmpty
                || summary.label.localizedCaseInsensitiveContains(query)
                || (summary.behind + summary.current).contains { $0.repo.localizedCaseInsensitiveContains(query) }
        }
        sections = PackageSection.Kind.allCases.compactMap { kind in
            let summaries = found.filter { kind.state == $0.state }
            guard !summaries.isEmpty else { return nil }
            return PackageSection(kind: kind, packages: summaries.map { summary in
                PackageRow(
                    summary: summary,
                    isNew: summary.state == .updateAvailable && seenAtOpen[summary.id] != summary.latest
                )
            })
        }
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
                        DisclosureTableRow(PackageNode.package(row)) {
                            ForEach(row.users) { user in
                                TableRow(PackageNode.user(user))
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
            if model.versionReport == nil {
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
        .navigationTitle(Text("Versies"))
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
        .onChange(of: Query(text: searchText, summaries: model.packageSummaries, seen: seenAtOpen), initial: true) {
            recompute()
        }
    }
}

/// Welke groepen in Versies open staan; "Nieuwe versie beschikbaar" standaard wel, de rest niet.
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

    var id: String { summary.id }

    /// Wie achterloopt eerst, daarna wie al actueel is.
    var users: [PackageUserRow] {
        summary.behind.map { PackageUserRow(packageId: summary.id, user: $0, isCurrent: false) }
            + summary.current.map { PackageUserRow(packageId: summary.id, user: $0, isCurrent: true) }
    }
}

/// Eén repo die een package gebruikt, als rij onder dat package.
struct PackageUserRow: Hashable, Identifiable {
    let packageId: String
    let user: PackageUser
    let isCurrent: Bool

    var id: String { "\(packageId)|\(user.repoId)" }
}

/// Een rij in de tabel: een package of een repo eronder.
enum PackageNode: Hashable, Identifiable {
    case package(PackageRow)
    case user(PackageUserRow)

    var id: String {
        switch self {
        case .package(let row): "package|\(row.id)"
        case .user(let row): "user|\(row.id)"
        }
    }

    /// De repo van een geselecteerde repo-rij, voor openen.
    static func repoId(in ids: Set<ID>) -> String? {
        guard ids.count == 1, let id = ids.first, id.hasPrefix("user|") else { return nil }
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
            Text(verbatim: row.user.repo).lineLimit(1)
                .help(Text("Dubbelklik om de pagina van deze repo te openen"))
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
            Label {
                Text(verbatim: row.user.version).monospacedDigit()
            } icon: {
                Image(systemName: row.isCurrent ? "checkmark.circle" : "arrow.down.circle")
                    .foregroundStyle(row.isCurrent ? .green : .orange)
            }
            .accessibilityLabel(row.isCurrent ? Text("\(row.user.version), actueel") : Text("\(row.user.version), loopt achter"))
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
                Text("Nieuwste versie niet op te halen").foregroundStyle(.secondary)
            }
        case .user(let row):
            Text(verbatim: row.user.sources.joined(separator: ", "))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .help(row.user.sources.joined(separator: "\n"))
        }
    }
}
