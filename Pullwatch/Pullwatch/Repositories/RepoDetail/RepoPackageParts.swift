import PullwatchCore
import SwiftUI

/// De packages van een repo als tabel, in dezelfde stijl als de kwetsbaarheden: package,
/// geïnstalleerde versie, de nieuwste die nu kan, de nieuwste, en de status. Een sectie per
/// workspace alleen als er meer zijn; meer installs van een package staan eronder.
struct RepoPackageTable: View {
    @Bindable var page: RepoPage
    let width: TableWidth
    /// De bronnen die bij de check uit stonden; een package van een register dat uit stond heeft
    /// geen nieuwste versie, en de status zegt waarom.
    var skippedSources: Set<DataSourceID> = []

    /// Een eigen package hangt niet aan het publieke register van zijn ecosysteem.
    private func skippedRegistry(of row: RepoPackageTableRow) -> DataSourceID? {
        guard row.row.inHouse == nil else { return nil }
        return DataSourceID.registry(ecosystem: row.row.package.ecosystem).flatMap { skippedSources.contains($0) ? $0 : nil }
    }

    private func isExpanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { page.expanded.contains(id) },
            set: { open in
                if open { page.expanded.insert(id) } else { page.expanded.remove(id) }
            }
        )
    }

    var body: some View {
        Table(of: RepoPackageTableRow.self, selection: $page.packageSelection, sortOrder: $page.packageSort) {
            TableColumn("Package", value: \.nameSortKey) { row in
                PackageNameCell(row: row)
            }
            .width(min: 120, ideal: 170)
            TableColumn("Geïnstalleerd", value: \.installedSortKey) { row in
                Text(verbatim: row.install?.version ?? row.row.installedText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
            .width(min: 84, ideal: 90)
            if width == .wide {
                TableColumn("Nu mogelijk", value: \.usableSortKey) { row in
                    Text(verbatim: row.install == nil ? row.row.newestUsable ?? "" : "")
                        .monospacedDigit()
                        .lineLimit(1)
                        .help(Text("De nieuwste versie die nu kan, met wat een ouder, peer of runtime toelaat"))
                        .accessibilityHidden(true)
                }
                .width(min: 64, ideal: 80)
            }
            if width != .narrow {
                TableColumn("Nieuwste", value: \.latestSortKey) { row in
                    Text(verbatim: row.install == nil ? row.row.latest ?? "" : "")
                        .monospacedDigit()
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
                .width(min: 64, ideal: 80)
            }
            TableColumn("Status", value: \.statusSortKey) { row in
                PackageStatusCell(row: row, skippedRegistry: skippedRegistry(of: row))
            }
            .width(min: 120, ideal: 170)
        } rows: {
            if page.packagesSpanWorkspaces {
                ForEach(page.visiblePackageGroups) { group in
                    Section {
                        PackageRows(rows: group.rows, isExpanded: isExpanded)
                    } header: {
                        Label(Workspace.name(group.workspace), systemImage: "folder")
                    }
                }
            } else {
                ForEach(page.visiblePackageGroups) { group in
                    PackageRows(rows: group.rows, isExpanded: isExpanded)
                }
            }
        }
        .contextMenu(forSelectionType: RepoPackageTableRow.ID.self) { ids in
            if let id = ids.first {
                Button("Toon details") {
                    page.packageSelection = id
                    page.showsInspector = true
                }
            }
        } primaryAction: { ids in
            if let id = ids.first {
                page.packageSelection = id
                page.showsInspector = true
            }
        }
        .onKeyPress(.space) {
            page.showsInspector.toggle()
            return .handled
        }
    }
}

/// De rijen van één workspace: een package, en zijn installs eronder als het er meer zijn.
private struct PackageRows: TableRowContent {
    typealias TableRowValue = RepoPackageTableRow

    let rows: [RepoPackageRow]
    let isExpanded: (String) -> Binding<Bool>

    var tableRowBody: some TableRowContent<RepoPackageTableRow> {
        ForEach(rows) { package in
            let row = RepoPackageTableRow(row: package)
            let children = row.children
            if children.isEmpty {
                TableRow(row)
            } else {
                DisclosureTableRow(row, isExpanded: isExpanded(row.id)) {
                    ForEach(children) { child in
                        TableRow(child)
                    }
                }
            }
        }
    }
}

/// De naam en daaronder hoe het binnenkomt; voor een install de keten. VoiceOver leest hier de
/// hele rij als één zin.
private struct PackageNameCell: View {
    let row: RepoPackageTableRow

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let install = row.install {
                Text(verbatim: install.version)
                    .monospacedDigit()
                    .lineLimit(1)
                Text(verbatim: install.provenanceText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                HStack(spacing: 6) {
                    Text(verbatim: row.row.name)
                        .lineLimit(1)
                    if let inHouse = row.row.inHouse {
                        InHouseBadge(inHouse: inHouse)
                    }
                }
                if let detail = row.row.detailText {
                    Text(verbatim: detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: row.spoken))
    }
}

private struct PackageStatusCell: View {
    let row: RepoPackageTableRow
    let skippedRegistry: DataSourceID?

    var body: some View {
        // Zonder nieuwste versie (een transitief package vraagt Pullwatch niet bij het register op)
        // leeg; stond het register uit, dan de vaste zin, want dan is er niets gecontroleerd.
        if let status = row.status {
            UpdateStatusLabel(status: status)
                .accessibilityHidden(true)
        } else if row.install == nil, let inHouse = row.row.inHouse, let text = SourceOff.inHouseNotChecked(inHouse) {
            Text(verbatim: text)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(Text(verbatim: SourceOff.inHouseHelp(inHouse) ?? text))
        } else if let skippedRegistry, row.install == nil {
            Text(verbatim: SourceOff.versionNotChecked(skippedRegistry))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(Text(verbatim: SourceOff.versionNotChecked(skippedRegistry)))
        }
    }
}

// MARK: - Inspectievenster

/// Het inspectievenster van één package: de versies, wat je ermee kunt en waarom, en elke install
/// met zijn keten en gevraagde bereik.
struct PackageInspector: View {
    let row: RepoPackageTableRow
    let showsWorkspace: Bool
    /// Het register van dit package stond uit bij de check (Instellingen, Bronnen).
    var skippedRegistry: DataSourceID? = nil
    var showPackage: ((String) -> Void)? = nil

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: row.row.name)
                        .font(.headline)
                        .textSelection(.enabled)
                    Text(verbatim: row.row.package.ecosystem)
                        .foregroundStyle(.secondary)
                    if let inHouse = row.row.inHouse {
                        InHouseBadge(inHouse: inHouse)
                        if let text = SourceOff.inHouseNotChecked(inHouse) {
                            SourceOffText(text: SourceOff.inHouseHelp(inHouse) ?? text)
                        }
                    }
                    if let skippedRegistry, row.row.inHouse == nil {
                        SourceOffText(text: SourceOff.versionNotChecked(skippedRegistry))
                    }
                    if let status = row.status {
                        UpdateStatusLabel(status: status)
                        if let reason = status.reason {
                            Text(reason)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            Section("Versies") {
                LabeledContent("Geïnstalleerd") {
                    Text(verbatim: row.row.installedVersions.joined(separator: ", ")).monospacedDigit()
                }
                if let usable = row.row.newestUsable {
                    LabeledContent("Nu mogelijk") { Text(verbatim: usable).monospacedDigit() }
                }
                LabeledContent("Nieuwste") {
                    Text(verbatim: row.row.latest ?? (skippedRegistry == nil && row.row.inHouse?.isChecked != false
                                                       ? String(localized: "Onbekend") : String(localized: "Niet gecontroleerd")))
                        .monospacedDigit()
                }
                if showsWorkspace {
                    LabeledContent("Workspace") { Text(verbatim: Workspace.name(row.row.workspace)) }
                }
            }
            Section("Installs") {
                ForEach(row.row.installs.isEmpty
                        ? row.row.package.installs.map { InstallUpdate(install: $0, update: PackageUpdate(status: .unknown, step: nil, latest: nil)) }
                        : row.row.installs, id: \.install) { install in
                    PackageInstallLine(install: install, isSelected: install.install == row.install, hasLatest: row.row.latest != nil)
                }
            }
            if let showPackage {
                Section {
                    Button("Toon \(row.row.name) in Afhankelijkheden") { showPackage(row.row.name) }
                        .buttonStyle(.link)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Eén install: versie, keten, gevraagd bereik en zijn eigen status.
private struct PackageInstallLine: View {
    let install: InstallUpdate
    let isSelected: Bool
    let hasLatest: Bool

    var body: some View {
        LabeledContent {
            if hasLatest {
                UpdateStatusLabel(status: UpdateStatus(install))
            }
        } label: {
            Text(verbatim: install.install.version)
                .monospacedDigit()
                .fontWeight(isSelected ? .semibold : .regular)
            Text(verbatim: install.install.provenanceText)
            if let requested = install.install.requested {
                Text("Gevraagd: \(requested)", comment: "Het bereik uit het manifest, bv. ^4.17.20")
            }
        }
        .help(Text(verbatim: install.install.source))
    }
}

extension RepoPackageRow {
    /// "4.17.20"; met meer versies het aantal (de versies staan in de rijen eronder).
    var installedText: String {
        let versions = installedVersions
        return versions.count > 1
            ? String(localized: "\(versions.count) versies", comment: "Aantal verschillende versies van een package in deze repo")
            : versions.joined(separator: ", ")
    }

    /// De regel onder de naam: transitief (met de ouder), onbekend of dev; niets voor direct.
    var detailText: String? {
        switch origin {
        case .direct: return nil
        case .transitive:
            let via = package.installs.first { $0.scope == .transitive }?.via ?? []
            return via.isEmpty ? String(localized: "Transitief") : Provenance.chain(via)
        case .unknown: return String(localized: "Herkomst onbekend")
        case .dev: return String(localized: "Alleen dev")
        }
    }
}

extension RepoPackageTableRow {
    /// De status van deze rij; nil zonder nieuwste versie.
    var status: UpdateStatus? {
        guard row.latest != nil else { return nil }
        if install != nil {
            return update.map(UpdateStatus.init)
        }
        return UpdateStatus(update: row.update, installed: row.leading?.install.version ?? row.installedVersions.first ?? "",
                            requested: row.leading?.install.requested)
    }

    /// De rij als één zin voor VoiceOver: naam, versie, nieuwste en status.
    var spoken: String {
        let status = status?.spoken ?? String(localized: "Nieuwste versie onbekend")
        if let install {
            return String(localized: "Install \(install.version), \(install.provenanceText), \(status)",
                          comment: "Voorgelezen install van een package: versie, herkomst, status")
        }
        return String(localized: "\(row.name) \(row.installedText), nieuwste \(row.latest ?? "?"), \(status)",
                      comment: "Voorgelezen package: naam, versie, nieuwste versie, status")
    }
}

extension PackageInstall {
    /// "Direct", "via express → body-parser" of "Transitief", met "alleen dev" erbij.
    var provenanceText: String {
        let how = Provenance.text(scope: scope, via: via) ?? String(localized: "Herkomst onbekend")
        return kind == .dev ? String(localized: "\(how), alleen dev", comment: "Herkomst, bv. Via jest") : how
    }
}
