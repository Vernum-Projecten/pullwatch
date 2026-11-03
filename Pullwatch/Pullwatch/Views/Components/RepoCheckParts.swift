import AppKit
import PullwatchCore
import SwiftUI

/// Eén taal of framework van een repo: versie, status en wat er in de laatste release stond.
struct ComponentRow: View {
    let component: ComponentVersion
    /// Nieuwste tag en hetzelfde onderdeel daarin; nil als de repo geen tags heeft.
    let release: (tag: String, component: ComponentVersion?)?
    /// De releasebron (endoflife.date, swift.org) stond uit: geen status, wel de vaste zin.
    var skippedSource: DataSourceID? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(component.label)
            Text(verbatim: component.versionText).monospacedDigit().foregroundStyle(.secondary)
            if let skippedSource {
                Text(verbatim: SourceOff.notChecked(skippedSource)).foregroundStyle(.secondary)
            } else {
                Pill(text: component.status.label, tint: component.status.color)
            }
            // Ter info, zonder status: wat op main al bijgewerkt is telt niet.
            if let release, let old = release.component, old.version != component.version {
                Text("\(old.version) in \(release.tag)", comment: "Versie in de laatste release, tagnaam")
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .help(component.sources.joined(separator: "\n"))
    }
}

extension ComponentVersion {
    var versionText: String {
        guard let latest, status != .current else { return version }
        return "\(version) → \(latest)"
    }
}

/// De kwetsbaarheden van een repo, inklapbaar: één regel per advies (direct eerst), met daaronder
/// elke install die het raakt, waar die zit en wat je moet bijwerken.
struct VulnerabilityList: View {
    let repo: RepoVersions
    /// Klik op een package dat in Afhankelijkheden staat; nil laat het package als tekst staan.
    var showPackage: ((String) -> Void)? = nil
    var knownPackages: Set<String> = []
    /// GitHubs advies per `Vulnerability.id` (`RepoSummary.advisories`).
    var gitHubAdvisories: [String: GitHubAdvisory] = [:]
    /// De GitHub Advisory Database staat uit: één regel boven de adviezen in plaats van de details.
    var advisoryDetailsOff = false

    @State private var isExpanded = true

    /// Hoeveel adviezen er ook in de laatste release zitten, met die tag; nil zonder gecheckte release.
    private func inRelease(_ advisories: [Advisory]) -> (count: Int, tag: String)? {
        guard let release = repo.release, release.error == nil else { return nil }
        return (advisories.filter { repo.isInRelease($0.first) == true }.count, release.tag)
    }

    var body: some View {
        let advisories = repo.advisories
        // De workspace alleen noemen als de geraakte installs er meer dan één beslaan.
        let showsWorkspace = Set(repo.vulnerabilities.map(\.workspace)).count > 1
        DisclosureGroup(isExpanded: $isExpanded) {
            if advisoryDetailsOff {
                Text(verbatim: SourceOff.detailsNotFetched(.gitHubAdvisoryDatabase))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(advisories) { advisory in
                AdvisoryRow(
                    advisory: advisory,
                    gitHub: gitHubAdvisories[advisory.first.id],
                    location: repo.location(of: advisory.first),
                    showsWorkspace: showsWorkspace,
                    showPackage: knownPackages.contains(advisory.first.package) ? showPackage : nil
                )
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Label("\(advisories.count) kwetsbaarheden", systemImage: "exclamationmark.shield")
                    .foregroundStyle(VersionStatus.eol.color)
                if let inRelease = inRelease(advisories) {
                    Text("\(inRelease.count) ook in \(inRelease.tag)", comment: "Aantal kwetsbaarheden, tagnaam")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Eén advies: ernst, id, package, of het direct of via een ander package binnenkomt, per geraakte
/// install de versie, plek en keten, en onderaan wat je moet bijwerken.
private struct AdvisoryRow: View {
    let advisory: Advisory
    /// GitHubs eigen gegevens (ernst, CVSS, CWE's); nil zonder advies in de Advisory Database.
    let gitHub: GitHubAdvisory?
    let location: VulnerabilityLocation?
    let showsWorkspace: Bool
    var showPackage: ((String) -> Void)? = nil

    private var vulnerability: Vulnerability { advisory.first }

    /// Elke oplossing één keer, op volgorde van de installs.
    private var fixes: [VulnerabilityFix] {
        advisory.installs.map(\.fix).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                let severity = gitHub?.severity ?? vulnerability.severity
                Pill(text: Vulnerability.severityLabel(severity), tint: Vulnerability.severityColor(severity))
                if let cvss = gitHub?.cvss {
                    Pill(text: "CVSS \(cvss.score.formatted(.number.precision(.fractionLength(1))))", tint: Vulnerability.severityColor(severity))
                        .help(Text(verbatim: cvss.vector ?? ""))
                }
                Link(vulnerability.cve ?? gitHub?.cveId ?? vulnerability.id, destination: vulnerability.url)
                    .help("Open bij OSV.dev")
                if let ghsa = vulnerability.ghsa ?? gitHub?.ghsaId, ghsa != vulnerability.cve ?? gitHub?.cveId ?? vulnerability.id {
                    Link(ghsa, destination: gitHub?.url ?? GitHubAdvisory.pageURL(ghsaId: ghsa))
                        .help("Open in de GitHub Advisory Database")
                }
                if let showPackage {
                    Button(vulnerability.package) { showPackage(vulnerability.package) }
                        .buttonStyle(.link)
                        .help("Toon dit package in Afhankelijkheden, met alle repo's die het gebruiken")
                } else {
                    Text(verbatim: vulnerability.package).foregroundStyle(.secondary)
                }
                if let scope = advisory.scopePill {
                    Pill(text: scope.text, tint: scope.tint)
                        .help(Text(scope.help))
                }
                if advisory.isDevOnly {
                    Pill(text: "Alleen dev", tint: .secondary)
                        .help(Text("Alleen nodig om te ontwikkelen en te testen, niet in wat je uitlevert"))
                }
                if let location {
                    Pill(text: location.label, tint: location.color)
                        .help(Text(location.help))
                }
            }
            if let summary = vulnerability.summary ?? gitHub?.summary {
                Text(verbatim: summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if let cweText = gitHub?.cweText {
                Text(verbatim: cweText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            ForEach(advisory.installs, id: \.installId) { install in
                InstallLine(
                    version: install.version,
                    fixedIn: install.fixedIn,
                    workspace: showsWorkspace ? install.workspace : nil,
                    scope: install.scope,
                    via: install.via,
                    isDev: install.kind == .dev && !advisory.isDevOnly
                )
                .help(Text(verbatim: "\(install.id)\n\(install.source)"))
            }
            ForEach(fixes, id: \.self) { fix in
                Label {
                    Text(fix.text)
                } icon: {
                    Image(systemName: fix == .none ? "clock" : "wrench.and.screwdriver")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
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
    /// De zinnen van vóór de blokkades; #85 geeft binnen bereik, manifest en elke blokkade een eigen zin.
    var text: LocalizedStringResource {
        switch self {
        case .update(let package, let version), .withinRange(let package, let version), .needsManifestChange(let package, let version):
            "Werk \(package) bij naar \(version)"
        case .blocked(_, _, .package(let parent, _, let minimum?)):
            "Werk \(parent) bij naar \(minimum)"
        case .blocked(let package, let version, .package(let parent, _, nil)):
            "Werk \(parent) bij, zodat het \(package) \(version) of nieuwer binnenhaalt"
        case .blocked(let package, let version, .peer), .blocked(let package, let version, .runtime):
            "Werk \(package) bij naar \(version)"
        case .updateParent(let parent, let package, let minimum): "Werk \(parent) bij, zodat het \(package) \(minimum) of nieuwer binnenhaalt"
        case .none: "Nog geen versie met een oplossing"
        }
    }
}

extension Advisory {
    /// "Direct", "Via express" of "Transitief"; nil als het niet te bepalen is.
    var scopePill: (text: LocalizedStringResource, tint: Color, help: LocalizedStringResource)? {
        if isDirect { return ("Direct", .blue, "Je project vraagt dit package zelf") }
        guard let transitive = installs.first(where: { $0.scope == .transitive }) else { return nil }
        if let parent = transitive.via.first {
            return ("Via \(parent)", .purple, "Komt binnen via \(parent), een package dat je project zelf vraagt")
        }
        return ("Transitief", .purple, "Komt binnen via een ander package")
    }
}

extension Vulnerability {
    /// Vaste id voor lijsten: hetzelfde advies kan meerdere packages, versies en workspaces raken.
    var rowId: String { installId }

    static func severityLabel(_ severity: String?) -> LocalizedStringResource {
        switch severity {
        case "CRITICAL": "Kritiek"
        case "HIGH": "Hoog"
        case "MODERATE", "MEDIUM": "Gemiddeld"
        case "LOW": "Laag"
        default: "Onbekend"
        }
    }

    static func severityColor(_ severity: String?) -> Color {
        switch severity {
        case "CRITICAL": .red
        case "HIGH": .orange
        case "MODERATE", "MEDIUM": .yellow
        default: .gray
        }
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
    /// per advies (met GitHubs ernst, CVSS en CWE's), met waar en hoe elke install erin komt, en de
    /// beveiligingsmeldingen van de dienst.
    /// `advisoryDetailsOff`: de GitHub Advisory Database staat uit, dus er zijn geen details van GitHub.
    func clipboardText(advisories gitHub: [String: GitHubAdvisory] = [:], advisoryDetailsOff: Bool = false) -> String {
        var lines = [repo]
        if let error { lines.append(String(localized: "Fout: \(error)", comment: "Foutmelding van de check")) }
        for component in components {
            let status = skippedReleaseSource(of: component).map(SourceOff.notChecked) ?? String(localized: component.status.label)
            lines.append("\(component.label) \(component.versionText) (\(status))")
        }
        if let release {
            lines.append(String(localized: "Laatste tag \(release.tag):", comment: "Kop in de gekopieerde tekst; tagnaam"))
            if let error = release.error { lines.append(String(localized: "Fout: \(error)", comment: "Foutmelding van de check")) }
            for component in release.components {
                lines.append("  \(component.label) \(component.versionText) (\(String(localized: component.status.label)))")
            }
        }
        // Alleen wat de repo zelf vraagt (met al zijn installs); de transitieve rest zou honderden regels zijn.
        let ownPackages = packages.flatMap { package in package.installs.map { (package.name, $0) } }
        if !ownPackages.isEmpty {
            lines.append(String(localized: "Packages:"))
            for (workspace, installs) in Dictionary(grouping: ownPackages, by: \.1.workspace)
                .sorted(by: { $0.key.isEmpty || (!$1.key.isEmpty && $0.key < $1.key) }) {
                lines.append("  \(Workspace.name(workspace)):")
                for (name, install) in installs {
                    let how = Provenance.line(scope: install.scope, via: install.via, workspace: "", kind: install.kind)
                    lines.append("    \(name) \(install.version)" + (how.map { " (\($0))" } ?? ""))
                }
            }
        }
        if let vulnerabilityError { lines.append(vulnerabilityError) }
        // Wat niet gecontroleerd is omdat een bron uit stond (een releasebron staat al bij het onderdeel).
        for source in skippedInOrder where source != .endOfLife && source != .swiftOrg {
            lines.append(SourceOff.isRegistry(source) ? SourceOff.versionNotChecked(source) : SourceOff.notChecked(source))
        }
        let advisories = advisories
        if !advisories.isEmpty {
            lines.append(String(localized: "Kwetsbaarheden:"))
            if advisoryDetailsOff { lines.append(SourceOff.detailsNotFetched(.gitHubAdvisoryDatabase)) }
            for advisory in advisories {
                let v = advisory.first
                let found = gitHub[v.id]
                var line = "- \(v.identifiers(found))"
                if let location = location(of: v) { line += " {\(String(localized: location.label))}" }
                if let severity = v.severityText(found) { line += " [\(severity)]" }
                line += " \(v.package)"
                if let summary = v.summary ?? found?.summary { line += ": \(summary)" }
                line += " (\((found?.url ?? v.url).absoluteString))"
                lines.append(line)
                if let vector = found?.cvss?.vector { lines.append("    \(vector)") }
                if let cweText = found?.cweText { lines.append("    \(cweText)") }
                for install in advisory.installs {
                    var installLine = "    \(install.version)"
                    if let fixedIn = install.fixedIn { installLine += " → \(fixedIn)" }
                    if let how = install.provenanceLine { installLine += ", \(how)" }
                    lines.append(installLine)
                }
                for fix in advisory.installs.compactMap(\.fix.plainText).reduce(into: [String](), { if !$0.contains($1) { $0.append($1) } }) {
                    lines.append("    \(fix)")
                }
            }
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
        case .unknown: .gray
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
