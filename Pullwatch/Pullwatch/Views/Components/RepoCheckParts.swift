import AppKit
import PullwatchCore
import SwiftUI

// MARK: - Samenvatting

/// De tellingen bovenaan de repo-pagina, elk een filter: kwetsbaarheden, verouderde runtimes,
/// packages die je nu kunt bijwerken en die geblokkeerd zijn, en waarmee vergeleken is. In een
/// smal venster alleen symbool en aantal.
struct RepoCheckSummaryBar: View {
    let summary: RepoCheckSummary
    let isActive: (RepoPage.SummaryFilter) -> Bool
    let apply: (RepoPage.SummaryFilter) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                SummaryCounters(summary: summary, compact: false, isActive: isActive, apply: apply)
                Spacer(minLength: 0)
                ComparedWithLabel(tag: summary.comparedWith)
            }
            VStack(alignment: .leading, spacing: 4) {
                SummaryCounters(summary: summary, compact: false, isActive: isActive, apply: apply)
                ComparedWithLabel(tag: summary.comparedWith)
            }
            VStack(alignment: .leading, spacing: 4) {
                SummaryCounters(summary: summary, compact: true, isActive: isActive, apply: apply)
                ComparedWithLabel(tag: summary.comparedWith)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct SummaryCounters: View {
    let summary: RepoCheckSummary
    let compact: Bool
    let isActive: (RepoPage.SummaryFilter) -> Bool
    let apply: (RepoPage.SummaryFilter) -> Void

    var body: some View {
        HStack(spacing: 6) {
            SummaryCounter(title: "Kwetsbaarheden", count: summary.vulnerabilities, symbol: "exclamationmark.shield.fill",
                           tint: .red, compact: compact, isOn: isActive(.vulnerabilities)) { apply(.vulnerabilities) }
            SummaryCounter(title: "Verouderd", count: summary.outdated, symbol: "clock.badge.exclamationmark.fill",
                           tint: .orange, compact: compact, isOn: isActive(.outdated)) { apply(.outdated) }
            SummaryCounter(title: "Kan bijwerken", count: summary.canUpdate, symbol: UpdateCategory.canUpdateNow.symbol,
                           tint: UpdateCategory.canUpdateNow.color, compact: compact, isOn: isActive(.canUpdate)) { apply(.canUpdate) }
            SummaryCounter(title: "Geblokkeerd", count: summary.blocked, symbol: UpdateCategory.blocked.symbol,
                           tint: UpdateCategory.blocked.color, compact: compact, isOn: isActive(.blocked)) { apply(.blocked) }
        }
    }
}

/// Eén teller: symbool, soort en aantal, als knop die het filter aan- en uitzet.
private struct SummaryCounter: View {
    let title: LocalizedStringResource
    let count: Int
    let symbol: String
    let tint: Color
    let compact: Bool
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in action() })) {
            Label {
                if !compact { Text(title) }
                Text(count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(count > 0 ? tint : Color.secondary)
            }
        }
        .toggleStyle(.button)
        .disabled(count == 0)
        .help(Text(title))
        .accessibilityLabel(Text("\(String(localized: title)): \(count)", comment: "Soort bevinding, aantal"))
    }
}

/// "Vergeleken met v1.2.0": de laatste release waarmee de controle vergelijkt.
private struct ComparedWithLabel: View {
    let tag: String?

    var body: some View {
        if let tag {
            Text("Vergeleken met \(tag)", comment: "Tagnaam van de laatste release")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(Text("Het symbool in de kolom In release zegt of een kwetsbaarheid ook in deze tag zit"))
        }
    }
}

// MARK: - Talen en frameworks

/// De talen, runtimes en frameworks als compact raster: naam, versie en een statussymbool. Met
/// `onlyOutdated` alleen wat achterloopt.
struct ComponentGrid: View {
    let components: [ComponentVersion]
    let release: ReleaseVersions?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 24, alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(components, id: \.label) { component in
                ComponentCell(component: component, inRelease: release?.components.first { $0.label == component.label }, tag: release?.tag)
            }
        }
    }
}

private struct ComponentCell: View {
    let component: ComponentVersion
    /// Hetzelfde onderdeel in de laatste release; nil zonder release of als het daar ontbreekt.
    let inRelease: ComponentVersion?
    let tag: String?

    private var help: String {
        var lines = component.sources
        if let inRelease, let tag, inRelease.version != component.version {
            lines.append(String(localized: "\(inRelease.version) in \(tag)", comment: "Versie in de laatste release, tagnaam"))
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(component.label)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(verbatim: component.versionText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: component.status.symbol)
                .foregroundStyle(component.status.color)
        }
        .help(Text(verbatim: help))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(component.label) \(component.versionText), \(String(localized: component.status.label))",
                                 comment: "Taal of framework, versie, status"))
    }
}

// MARK: - Kwetsbaarheden

/// Welke kolommen passen: in een smal venster (of met het inspectievenster open) gaan Waar en In
/// release weg, en daarna Geïnstalleerd; die staan ook in het inspectievenster.
enum TableWidth {
    case wide, medium, narrow

    init(_ width: CGFloat) {
        self = width >= 760 ? .wide : width >= 560 ? .medium : .narrow
    }
}

/// De kwetsbaarheden van een repo als tabel: één rij per advies, de installs eronder als het er
/// meer zijn. Pijltjes kiezen een rij, spatie of dubbelklik opent het inspectievenster.
struct VulnerabilityTable: View {
    @Bindable var page: RepoPage
    let releaseTag: String?
    let width: TableWidth
    let openAdvisory: (VulnerabilityRow) -> Void

    private func isExpanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { page.expanded.contains(id) },
            set: { open in
                if open { page.expanded.insert(id) } else { page.expanded.remove(id) }
            }
        )
    }

    var body: some View {
        let showsWorkspace = page.vulnerabilitiesSpanWorkspaces
        Table(of: VulnerabilityTableRow.self, selection: $page.vulnerabilitySelection, sortOrder: $page.vulnerabilitySort) {
            TableColumn("Ernst", value: \.severitySortKey) { row in
                SeverityCell(row: row, releaseTag: releaseTag, showsWorkspace: showsWorkspace)
            }
            .width(min: 104, ideal: 116, max: 140)
            TableColumn("Advies", value: \.advisorySortKey) { row in
                AdvisoryCell(row: row, showsWorkspace: showsWorkspace)
            }
            .width(min: 130, ideal: 180)
            if width != .narrow {
                TableColumn("Geïnstalleerd", value: \.installedSortKey) { row in
                    InstalledCell(row: row)
                }
                .width(min: 64, ideal: 90)
            }
            TableColumn("Oplossing", value: \.fixSortKey) { row in
                FixCell(row: row)
            }
            .width(min: 64, ideal: 90)
            if width == .wide {
                TableColumn("Waar", value: \.whereSortKey) { row in
                    WhereCell(row: row, showsWorkspace: showsWorkspace)
                }
                .width(min: 80, ideal: 130)
                if let releaseTag {
                    TableColumn(Text("In \(releaseTag)", comment: "Kolomkop: zit het ook in deze tag"), value: \.releaseSortKey) { row in
                        ReleaseMark(inRelease: row.install == nil ? row.row.inRelease : nil, tag: releaseTag)
                    }
                    .width(min: 44, ideal: 64, max: 90)
                }
            }
        } rows: {
            ForEach(page.visibleVulnerabilities) { row in
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
        .contextMenu(forSelectionType: VulnerabilityTableRow.ID.self) { ids in
            if let id = ids.first, let row = page.visibleVulnerabilities.first(where: { $0.id == id || $0.children.contains { $0.id == id } }) {
                Button("Toon details") {
                    page.vulnerabilitySelection = id
                    page.showsInspector = true
                }
                Button("Open advies") { openAdvisory(row.row) }
                Button("Kopieer id") { Pasteboard.copy(row.row.primaryId) }
            }
        } primaryAction: { ids in
            if let id = ids.first {
                page.vulnerabilitySelection = id
                page.showsInspector = true
            }
        }
        .onKeyPress(.space) {
            page.showsInspector.toggle()
            return .handled
        }
    }
}

/// De ernst met symbool en woord. VoiceOver leest hier de hele rij als één zin; de andere cellen
/// zeggen niets, zodat de rij niet in stukjes komt.
private struct SeverityCell: View {
    let row: VulnerabilityTableRow
    let releaseTag: String?
    let showsWorkspace: Bool

    var body: some View {
        if row.install == nil {
            SeverityLabel(level: row.row.severity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: row.row.spoken(releaseTag: releaseTag, showsWorkspace: showsWorkspace)))
        } else if let install = row.install {
            Text(verbatim: "")
                .accessibilityLabel(Text(verbatim: install.spoken(showsWorkspace: showsWorkspace)))
        }
    }
}

/// Symbool en woord van een ernst; onbekend zonder kleur.
struct SeverityLabel: View {
    let level: SeverityLevel

    var body: some View {
        Label {
            Text(level.label)
                .foregroundStyle(level == .unknown ? .secondary : .primary)
        } icon: {
            Image(systemName: level.symbol)
                .foregroundStyle(level.color)
        }
        .lineLimit(1)
    }
}

/// Het hoofd-id en daaronder het package; voor een install de workspace en de keten.
private struct AdvisoryCell: View {
    let row: VulnerabilityTableRow
    let showsWorkspace: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let install = row.install {
                Text(verbatim: install.placeText(showsWorkspace: showsWorkspace))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: row.row.primaryId)
                    .lineLimit(1)
                Text(verbatim: row.row.package)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .help(Text(verbatim: row.row.summary ?? row.row.primaryId))
        .accessibilityHidden(true)
    }
}

private struct InstalledCell: View {
    let row: VulnerabilityTableRow

    var body: some View {
        Text(verbatim: row.install?.version ?? row.row.installedText)
            .monospacedDigit()
            .lineLimit(1)
            .accessibilityHidden(true)
    }
}

private struct FixCell: View {
    let row: VulnerabilityTableRow

    var body: some View {
        let fixedIn = row.install.map(\.fixedIn) ?? row.row.fixedIn
        Group {
            if let fixedIn {
                Text(verbatim: fixedIn).monospacedDigit()
            } else if row.install == nil && row.row.hasFix {
                // Niet elke install heeft al een oplossing: de details staan eronder.
                Text("Deels").foregroundStyle(.secondary)
            } else {
                Text("Nog geen").foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .accessibilityHidden(true)
    }
}

private struct WhereCell: View {
    let row: VulnerabilityTableRow
    let showsWorkspace: Bool

    var body: some View {
        Text(verbatim: row.install.map { $0.whereText(showsWorkspace: showsWorkspace) } ?? row.row.whereText(showsWorkspace: showsWorkspace))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityHidden(true)
    }
}

/// Een klein symbool voor "zit ook in de laatste release"; een streepje voor alleen main.
private struct ReleaseMark: View {
    let inRelease: Bool?
    let tag: String

    var body: some View {
        switch inRelease {
        case true?:
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(.secondary)
                .help(Text("Zit ook in de laatste release (\(tag))"))
                .accessibilityHidden(true)
        case false?:
            Image(systemName: "minus")
                .foregroundStyle(.tertiary)
                .help(Text("Nieuw sinds de laatste release; nog niet uitgebracht"))
                .accessibilityHidden(true)
        case nil:
            EmptyView()
        }
    }
}

/// Het klembord, op één plek.
enum Pasteboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

extension SeverityLevel {
    var label: LocalizedStringResource {
        switch self {
        case .critical: "Kritiek"
        case .high: "Hoog"
        case .moderate: "Gemiddeld"
        case .low: "Laag"
        case .unknown: "Onbekend"
        }
    }

    /// Elke ernst een eigen vorm, zodat de kleur niet de enige aanwijzing is.
    var symbol: String {
        switch self {
        case .critical: "exclamationmark.octagon.fill"
        case .high: "exclamationmark.triangle.fill"
        case .moderate: "exclamationmark.circle.fill"
        case .low: "info.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .critical: .red
        case .high: .orange
        case .moderate: .yellow
        case .low: .blue
        case .unknown: .secondary
        }
    }
}

extension VulnerabilityRow {
    /// "4.17.20" of "4.17.15, 4.17.20"; met meer dan twee versies het aantal.
    var installedText: String {
        let versions = installedVersions
        return versions.count > 2
            ? String(localized: "\(versions.count) versies", comment: "Aantal verschillende versies van een package in deze repo")
            : versions.joined(separator: ", ")
    }

    /// Waar het zit: de workspaces als de repo er meer heeft, anders hoe het binnenkomt.
    func whereText(showsWorkspace: Bool) -> String {
        if showsWorkspace { return workspaces.map(Workspace.name).joined(separator: ", ") }
        let how: String
        switch origin {
        case .direct: how = String(localized: "Direct")
        case .transitive, .dev:
            how = parent.map { String(localized: "Via \($0)", comment: "Het package waarlangs een kwetsbaar package binnenkomt") }
                ?? String(localized: "Transitief")
        case .unknown: how = String(localized: "Onbekend")
        }
        return origin == .dev ? String(localized: "\(how), alleen dev", comment: "Herkomst, bv. Via jest") : how
    }

    /// De rij als één zin voor VoiceOver: ernst, id, package en versie, oplossing, waar, release.
    func spoken(releaseTag: String?, showsWorkspace: Bool) -> String {
        let fix = fixedIn.map { String(localized: "opgelost in \($0)", comment: "Versie met de oplossing") }
            ?? String(localized: "nog geen oplossing")
        var sentence = String(localized: "\(String(localized: severity.label)): \(primaryId) in \(package) \(installedText), \(fix), \(whereText(showsWorkspace: showsWorkspace))",
                              comment: "Voorgelezen rij: ernst, id, package, versie, oplossing, herkomst")
        if let releaseTag, let inRelease {
            sentence += ", " + (inRelease
                                ? String(localized: "ook in \(releaseTag)", comment: "Tagnaam")
                                : String(localized: "alleen main"))
        }
        return sentence
    }
}

extension Vulnerability {
    /// Voor een install onder een advies: de workspace en de keten ("Root, via express → body-parser").
    func placeText(showsWorkspace: Bool) -> String {
        let how = Provenance.text(scope: scope, via: via) ?? String(localized: "Onbekend")
        let place = showsWorkspace ? String(localized: "\(Workspace.name(workspace)), \(how)", comment: "Workspace, herkomst") : how
        return kind == .dev ? String(localized: "\(place), alleen dev", comment: "Herkomst, bv. Via jest") : place
    }

    /// Onder een advies staat de keten al in de kolom Advies; hier alleen de workspace.
    func whereText(showsWorkspace: Bool) -> String {
        showsWorkspace ? Workspace.name(workspace) : ""
    }

    /// Een install als één zin voor VoiceOver.
    func spoken(showsWorkspace: Bool) -> String {
        let fix = fixedIn.map { String(localized: "opgelost in \($0)", comment: "Versie met de oplossing") }
            ?? String(localized: "nog geen oplossing")
        let place = showsWorkspace
            ? String(localized: "\(Workspace.name(workspace)), \(Provenance.spoken(scope: scope, via: via) ?? "")", comment: "Workspace, herkomst")
            : (Provenance.spoken(scope: scope, via: via) ?? "")
        return String(localized: "Install \(version), \(fix), \(place)", comment: "Voorgelezen install: versie, oplossing, herkomst")
    }
}

extension ComponentVersion {
    var versionText: String {
        guard let latest, status != .current else { return version }
        return "\(version) → \(latest)"
    }
}

/// Eén install onder een advies of package: versie, workspace en keten. VoiceOver leest de keten
/// als "via express, dan body-parser".
struct InstallLine: View {
    /// nil zonder versie (een tabelcel met de versie in een eigen kolom).
    var version: String? = nil
    var fixedIn: String? = nil
    /// nil als de workspace niet genoemd hoeft te worden.
    var workspace: String? = nil
    let scope: DependencyScope
    let via: [String]
    var isDev = false
    var font: Font = .caption

    var body: some View {
        HStack(spacing: 6) {
            if let version {
                Text(verbatim: fixedIn.map { "\(version) → \($0)" } ?? version)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            if let workspace {
                Label(Workspace.name(workspace), systemImage: "folder")
                    .labelStyle(.titleAndIcon)
            }
            if let provenance = Provenance.text(scope: scope, via: via) {
                Text(verbatim: provenance)
                    .accessibilityLabel(Text(verbatim: Provenance.spoken(scope: scope, via: via) ?? provenance))
            }
            if isDev {
                Pill(text: "Dev", tint: .secondary)
            }
        }
        .font(font)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// Hoe een install in een project komt, als tekst.
enum Provenance {
    /// "Direct", "via express → body-parser" of "Transitief"; nil als het niet te bepalen is.
    static func text(scope: DependencyScope, via: [String]) -> String? {
        switch scope {
        case .direct: String(localized: "Direct")
        case .transitive where !via.isEmpty: chain(via)
        case .transitive: String(localized: "Transitief")
        case .unknown: nil
        }
    }

    /// "via express → body-parser".
    static func chain(_ via: [String]) -> String {
        String(localized: "via \(via.joined(separator: " → "))", comment: "Keten van packages, bv. express → body-parser")
    }

    /// Voor VoiceOver: "via express, dan body-parser".
    static func spoken(scope: DependencyScope, via: [String]) -> String? {
        guard scope == .transitive, let first = via.first else { return text(scope: scope, via: via) }
        let chain = via.dropFirst().reduce(first) { chain, next in
            String(localized: "\(chain), dan \(next)", comment: "Voorgelezen keten van packages: wat er al staat, het volgende package")
        }
        return String(localized: "via \(chain)", comment: "Keten van packages, bv. express → body-parser")
    }

    /// Eén regel voor een melding of het klembord: hoe en waar, en of het alleen dev is.
    static func line(scope: DependencyScope, via: [String], workspace: String, kind: DependencyKind) -> String? {
        let place: String?
        switch scope {
        case .direct:
            place = workspace.isEmpty ? String(localized: "Direct") : String(localized: "Direct in \(workspace)", comment: "Workspace, bv. packages/web")
        case .transitive where !via.isEmpty:
            place = workspace.isEmpty
                ? chain(via)
                : String(localized: "via \(via.joined(separator: " → ")) in \(workspace)", comment: "Keten van packages, workspace")
        case .transitive:
            place = workspace.isEmpty ? String(localized: "Transitief") : String(localized: "Transitief in \(workspace)", comment: "Workspace, bv. packages/web")
        case .unknown:
            place = workspace.isEmpty ? nil : String(localized: "In \(workspace)", comment: "Workspace, bv. packages/web")
        }
        let dev = kind == .dev ? String(localized: "Alleen dev") : nil
        let parts = [place, dev].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// De naam van een workspace: "Root" voor de hoofdmap.
enum Workspace {
    static func name(_ workspace: String) -> String {
        workspace.isEmpty ? String(localized: "Root", comment: "De hoofdmap van een repo, als workspace") : workspace
    }
}

extension VulnerabilityFix {
    /// Wat je moet bijwerken, en of dat binnen het bereik kan, het manifest vraagt of eerst iets
    /// anders (een ouder, een peer, de runtime).
    var text: LocalizedStringResource {
        switch self {
        case .update(let package, let version):
            "Werk \(package) bij naar \(version)"
        case .withinRange(let package, let version):
            "Werk \(package) bij naar \(version); dat valt binnen het bereik, alleen de lockfile verandert"
        case .needsManifestChange(let package, let version):
            "Werk \(package) bij naar \(version); dat valt buiten het bereik, pas het manifest aan"
        case .blocked(let package, let version, .package(let parent, let range, let minimum?)):
            "\(package) \(version) wordt tegengehouden door \(parent), dat \(range) vraagt. Werk eerst \(parent) bij naar \(minimum)."
        case .blocked(let package, let version, .package(let parent, _, nil)):
            "Werk \(parent) bij, zodat het \(package) \(version) of nieuwer binnenhaalt"
        case .blocked(let package, let version, .peer(let name, let needs, let installed)):
            "\(package) \(version) vraagt \(name) \(needs); deze workspace heeft \(installed). Werk eerst \(name) bij."
        case .blocked(let package, let version, .runtime(let runtime, let needs, let installed)):
            "\(package) \(version) vraagt \(Runtime.name(runtime)) \(needs); de repo gebruikt \(installed). Werk eerst \(Runtime.name(runtime)) bij."
        case .updateParent(let parent, let package, let minimum): "Werk \(parent) bij, zodat het \(package) \(minimum) of nieuwer binnenhaalt"
        case .none: "Nog geen versie met een oplossing"
        }
    }

    var symbol: String {
        switch self {
        case .update, .updateParent: "wrench.and.screwdriver"
        case .withinRange: UpdateCategory.canUpdateNow.symbol
        case .needsManifestChange: UpdateCategory.needsManifestChange.symbol
        case .blocked: UpdateCategory.blocked.symbol
        case .none: "clock"
        }
    }

    var color: Color {
        switch self {
        case .withinRange: UpdateCategory.canUpdateNow.color
        case .needsManifestChange: UpdateCategory.needsManifestChange.color
        case .blocked: UpdateCategory.blocked.color
        case .update, .updateParent, .none: .secondary
        }
    }
}

extension Vulnerability {
    /// Vaste id voor lijsten: hetzelfde advies kan meerdere packages, versies en workspaces raken.
    var rowId: String { installId }

    static func severityLabel(_ severity: String?) -> LocalizedStringResource {
        SeverityLevel(severity).label
    }

    /// Hoe en waar deze install in de repo zit, voor een melding of het klembord.
    var provenanceLine: String? {
        Provenance.line(scope: scope, via: via, workspace: workspace, kind: kind)
    }
}

extension VulnerabilityFix {
    /// Als platte tekst; nil zonder bekende oplossing.
    var plainText: String? {
        self == .none ? nil : String(localized: text)
    }
}

/// Of een kwetsbaarheid van main ook in de laatste release zit.
enum VulnerabilityLocation {
    case alsoInRelease(tag: String)
    case mainOnly

    var label: LocalizedStringResource {
        switch self {
        case .alsoInRelease(let tag): "ook in \(tag)"
        case .mainOnly: "alleen main"
        }
    }

    var help: LocalizedStringResource {
        switch self {
        case .alsoInRelease(let tag): "Zit ook in de laatste release (\(tag))"
        case .mainOnly: "Nieuw sinds de laatste release; nog niet uitgebracht"
        }
    }

    var color: Color {
        switch self {
        case .alsoInRelease: .red
        case .mainOnly: .orange
        }
    }
}

extension RepoVersions {
    /// nil als er geen release gecheckt is.
    func location(of vulnerability: Vulnerability) -> VulnerabilityLocation? {
        guard let release, let inRelease = isInRelease(vulnerability) else { return nil }
        return inRelease ? .alsoInRelease(tag: release.tag) : .mainOnly
    }

    /// Platte tekst voor het klembord: repo, onderdelen, packages per workspace, kwetsbaarheden
    /// per advies (id met database en alle andere ids, ernst met CVSS en waar die vandaan komt,
    /// CWE's, de fix-links), met waar en hoe elke install erin komt, de ingetrokken adviezen, en
    /// de beveiligingsmeldingen van de dienst.
    func clipboardText(advisories gitHub: [String: GitHubAdvisory] = [:], report: VersionReport? = nil) -> String {
        let context = report?.updateContext(for: self) ?? .empty
        var lines = [repo]
        if let error { lines.append(String(localized: "Fout: \(error)", comment: "Foutmelding van de check")) }
        for component in components {
            lines.append("\(component.label) \(component.versionText) (\(String(localized: component.status.label)))")
        }
        if let release {
            lines.append(String(localized: "Laatste tag \(release.tag):", comment: "Kop in de gekopieerde tekst; tagnaam"))
            if let error = release.error { lines.append(String(localized: "Fout: \(error)", comment: "Foutmelding van de check")) }
            for component in release.components {
                lines.append("  \(component.label) \(component.versionText) (\(String(localized: component.status.label)))")
            }
        }
        // Alleen wat de repo zelf vraagt (met al zijn installs); de transitieve rest zou honderden regels zijn.
        let ownPackages = packages.flatMap { package in package.installs.map { (package, $0) } }
        if !ownPackages.isEmpty {
            lines.append(String(localized: "Packages:"))
            for (workspace, installs) in Dictionary(grouping: ownPackages, by: \.1.workspace)
                .sorted(by: { $0.key.isEmpty || (!$1.key.isEmpty && $0.key < $1.key) }) {
                lines.append("  \(Workspace.name(workspace)):")
                for (package, install) in installs {
                    let how = Provenance.line(scope: install.scope, via: install.via, workspace: "", kind: install.kind)
                    var line = "    \(package.name) \(install.version)" + (how.map { " (\($0))" } ?? "")
                    // De status alleen als er een nieuwere versie is: wat kan, en wat eerst moet.
                    if let latest = report?.latestPackages[package.key]?.version {
                        let status = UpdateStatus(
                            update: install.update(ecosystem: package.ecosystem, name: package.name, latest: latest, context: context),
                            installed: install.version, requested: install.requested
                        )
                        if status.category != .upToDate { line += ": \(String(localized: status.label)), \(latest)" }
                        lines.append(line)
                        if let reason = status.reason { lines.append("      \(String(localized: reason))") }
                        if let usable = status.usableNow { lines.append("      \(String(localized: "Nieuwste die nu kan: \(usable)"))") }
                    } else {
                        lines.append(line)
                    }
                }
            }
        }
        if let vulnerabilityError { lines.append(vulnerabilityError) }
        let advisories = advisories
        if !advisories.isEmpty {
            lines.append(String(localized: "Kwetsbaarheden:"))
            for advisory in advisories {
                let v = advisory.first
                let found = gitHub[v.id]
                var line = "- \(v.identifiers(found))"
                if let location = location(of: v) { line += " {\(String(localized: location.label))}" }
                if let severity = v.severityText(found) { line += " [\(severity)]" }
                line += " \(v.package)"
                if let summary = v.summary ?? found?.summary { line += ": \(summary)" }
                line += " (\(v.pageURL.absoluteString))"
                lines.append(line)
                let assessment = v.severityAssessment(found)
                lines.append("    \(assessment.note(for: v))")
                if let vector = assessment.vector { lines.append("    \(vector)") }
                if let cweText = found?.cweText { lines.append("    \(cweText)") }
                for reference in v.references where reference.type == "FIX" {
                    lines.append("    \(String(localized: "Oplossing: \(reference.url.absoluteString)", comment: "Link naar de fix-commit of -release"))")
                }
                for install in advisory.installs {
                    var installLine = "    \(install.version)"
                    if let fixedIn = install.fixedIn { installLine += " → \(fixedIn)" }
                    if let how = install.provenanceLine { installLine += ", \(how)" }
                    lines.append(installLine)
                }
                for fix in advisory.installs.compactMap({ $0.fix(in: context).plainText }).reduce(into: [String](), { if !$0.contains($1) { $0.append($1) } }) {
                    lines.append("    \(fix)")
                }
            }
        }
        if !withdrawnVulnerabilities.isEmpty {
            let ids = Array(Set(withdrawnVulnerabilities.map(\.id))).sorted().joined(separator: ", ")
            lines.append(String(localized: "Ingetrokken, niet meegeteld: \(ids)", comment: "Ids van ingetrokken adviezen"))
        }
        if let security { lines += security.clipboardLines }
        return lines.joined(separator: "\n")
    }
}

extension VersionStatus {
    var color: Color {
        switch self {
        case .current: .green
        case .behind: .orange
        case .eol: .red
        case .unknown: .secondary
        }
    }

    /// Elke stand een eigen vorm, zodat de kleur niet de enige aanwijzing is.
    var symbol: String {
        switch self {
        case .current: "checkmark.circle.fill"
        case .behind: "arrow.up.circle.fill"
        case .eol: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .current: "Actueel"
        case .behind: "Achter"
        case .eol: "EOL"
        case .unknown: "Onbekend"
        }
    }
}
