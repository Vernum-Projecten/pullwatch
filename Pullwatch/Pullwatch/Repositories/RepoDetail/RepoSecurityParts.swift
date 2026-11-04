import PullwatchCore
import SwiftUI

/// Per bron van de dienst (code scanning, secret scanning, eigen adviezen, Advanced Security)
/// wat er is, in hetzelfde compacte raster als de runtimes: de bron en de stand, met een link
/// als er iets goed te keuren of te openen is.
struct SecurityFeedGrid: View {
    let scan: SecurityScan
    let provider: ProviderKind

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 24, alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(scan.feeds, id: \.kind) { feed in
                SecurityFeedCell(feed: feed, scan: scan, provider: provider)
            }
        }
    }
}

private struct SecurityFeedCell: View {
    let feed: SecurityFeed
    let scan: SecurityScan
    let provider: ProviderKind

    var body: some View {
        HStack(spacing: 6) {
            Text(feed.kind.title)
                .lineLimit(1)
            Spacer(minLength: 8)
            SecurityFeedState(feed: feed, scan: scan, provider: provider)
        }
        .accessibilityElement(children: .combine)
    }
}

/// De stand van één bron: het aantal (een link naar de dienst), of waarom er niets is.
private struct SecurityFeedState: View {
    let feed: SecurityFeed
    let scan: SecurityScan
    let provider: ProviderKind

    var body: some View {
        switch feed.availability {
        case .available:
            if let count = count, count > 0, let link = feed.link {
                Link(destination: link) {
                    Text(count, format: .number).monospacedDigit()
                }
                .help(Text("Open bij de dienst"))
            } else {
                Text(count ?? 0, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        case .needsPermission:
            if let link = feed.link {
                Link(provider == .gitHub ? "Goedkeuren" : "Tokens", destination: link)
                    .help(provider == .gitHub
                          ? Text("De eigenaar moet het nieuwe recht van de Pullwatch-app goedkeuren bij de installatie op GitHub")
                          : Text("Het token mag Advanced Security niet lezen; geef het de scope Advanced Security (lezen)"))
            } else {
                Text("Toestemming nodig").foregroundStyle(.secondary)
            }
        case .notEnabled:
            Text("Staat uit").foregroundStyle(.secondary)
        case .notAvailable:
            Text("Niet beschikbaar").foregroundStyle(.secondary)
                .help(Text("Niet beschikbaar op deze server"))
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .help(Text(verbatim: feed.message ?? ""))
                .accessibilityLabel(Text(verbatim: feed.message ?? ""))
        }
    }

    private var count: Int? {
        switch feed.kind {
        case .codeScanning: scan.alerts.filter { $0.source == .codeScanning }.count
        case .advancedSecurity: scan.alerts.filter { $0.source == .advancedSecurity }.count + (scan.secretCount ?? 0)
        case .secretScanning: scan.secretCount
        case .repositoryAdvisories: scan.advisories.count
        }
    }
}

/// De vondsten van de dienst als tabel: ernst, titel, plek en bron.
struct SecurityFindingTable: View {
    @Bindable var page: RepoPage
    let width: TableWidth

    var body: some View {
        Table(page.visibleSecurity, selection: $page.securitySelection, sortOrder: $page.securitySort) {
            TableColumn("Ernst", value: \.severityRank) { row in
                FindingSeverityLabel(row: row)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: row.spoken))
            }
            .width(min: 110, ideal: 120, max: 150)
            TableColumn("Titel", value: \.titleSortKey) { row in
                Text(verbatim: row.title)
                    .lineLimit(1)
                    .help(Text(verbatim: row.title))
                    .accessibilityHidden(true)
            }
            .width(min: 140, ideal: 260)
            if width != .narrow {
                TableColumn("Waar", value: \.placeSortKey) { row in
                    Text(verbatim: row.place)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
                .width(min: 80, ideal: 150)
            }
            if width == .wide {
                TableColumn("Bron") { row in
                    Text(row.sourceTitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
                .width(min: 80, ideal: 120)
            }
        }
        .contextMenu(forSelectionType: SecurityFindingRow.ID.self) { ids in
            if let id = ids.first, let row = page.visibleSecurity.first(where: { $0.id == id }) {
                Button("Toon details") {
                    page.securitySelection = id
                    page.showsInspector = true
                }
                Link("Open bij de dienst", destination: row.url)
            }
        } primaryAction: { ids in
            if let id = ids.first {
                page.securitySelection = id
                page.showsInspector = true
            }
        }
        .onKeyPress(.space) {
            page.showsInspector.toggle()
            return .handled
        }
    }
}

/// De ernst van een vondst: de beveiligingsernst, anders die van de tool.
private struct FindingSeverityLabel: View {
    let row: SecurityFindingRow

    var body: some View {
        switch row {
        case .alert(let alert) where alert.severity == nil:
            Label {
                Text(alert.severityLabel)
            } icon: {
                Image(systemName: alert.toolSeverity == "error" ? "xmark.circle.fill" : "info.circle")
                    .foregroundStyle(alert.toolSeverity == "error" ? Color.yellow : Color.secondary)
            }
            .lineLimit(1)
        case .alert(let alert):
            SeverityLabel(level: SeverityLevel(alert.severity))
        case .ownAdvisory(let advisory):
            SeverityLabel(level: SeverityLevel(advisory.severity))
        }
    }
}

/// Het inspectievenster van één vondst van de dienst.
struct SecurityFindingInspector: View {
    let row: SecurityFindingRow

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    FindingSeverityLabel(row: row)
                    Text(verbatim: row.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Text(row.sourceTitle)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            switch row {
            case .alert(let alert):
                Section("Details") {
                    if let location = alert.locationText {
                        LabeledContent("Bestand") { Text(verbatim: location).textSelection(.enabled) }
                    }
                    if let package = alert.package {
                        LabeledContent("Package") { Text(verbatim: package) }
                    }
                    if let rule = alert.ruleText {
                        LabeledContent("Regel") { Text(verbatim: rule).textSelection(.enabled) }
                    }
                    if let created = alert.createdAt {
                        LabeledContent("Gevonden") { Text(created, format: .dateTime.day().month().year()) }
                    }
                }
            case .ownAdvisory(let advisory):
                Section("Details") {
                    LabeledContent("Id") { Text(verbatim: advisory.ghsaId).textSelection(.enabled) }
                    if let cve = advisory.cveId {
                        LabeledContent(String(localized: "CVE")) { Text(verbatim: cve).textSelection(.enabled) }
                    }
                    if let cvss = advisory.cvss {
                        LabeledContent {
                            Text(cvss.score, format: .number.precision(.fractionLength(1))).monospacedDigit()
                        } label: {
                            Text(verbatim: cvss.version.map { "CVSS \($0)" } ?? "CVSS")
                            if let vector = cvss.vector { Text(verbatim: vector).textSelection(.enabled) }
                        }
                    }
                    if let published = advisory.publishedAt {
                        LabeledContent("Gepubliceerd") { Text(published, format: .dateTime.day().month().year()) }
                    }
                }
                if !advisory.packages.isEmpty {
                    Section("Getroffen packages") {
                        ForEach(advisory.packages, id: \.self) { package in
                            Text(verbatim: package.line).monospacedDigit()
                        }
                    }
                }
            }
            Section {
                Link(destination: row.url) {
                    Label("Open bij de dienst", systemImage: "safari")
                }
            }
        }
        .formStyle(.grouped)
    }
}

extension SecurityFindingRow {
    var sourceTitle: LocalizedStringResource {
        switch self {
        case .alert(let alert): alert.source == .codeScanning ? "Code scanning" : "Advanced Security"
        case .ownAdvisory: "Eigen advies"
        }
    }

    /// De rij als één zin voor VoiceOver: ernst, titel, plek, bron.
    var spoken: String {
        let severity: String
        switch self {
        case .alert(let alert): severity = String(localized: alert.severityLabel)
        case .ownAdvisory(let advisory): severity = String(localized: SeverityLevel(advisory.severity).label)
        }
        let place = self.place.isEmpty ? String(localized: sourceTitle) : "\(self.place), \(String(localized: sourceTitle))"
        return String(localized: "\(severity): \(title), \(place)", comment: "Voorgelezen vondst: ernst, titel, plek en bron")
    }
}

extension SecurityFeed.Kind {
    var title: LocalizedStringResource {
        switch self {
        case .codeScanning: "Code scanning"
        case .secretScanning: "Secret scanning"
        case .repositoryAdvisories: "Eigen adviezen"
        case .advancedSecurity: "Meldingen"
        }
    }
}

extension SecurityAlert {
    /// De beveiligingsernst, anders die van de tool ("Fout", "Waarschuwing", "Opmerking").
    var severityLabel: LocalizedStringResource {
        if severity != nil { return Vulnerability.severityLabel(severity) }
        switch toolSeverity {
        case "error": return "Fout"
        case "warning": return "Waarschuwing"
        case "note": return "Opmerking"
        default: return "Onbekend"
        }
    }

    /// "src/db.js:42".
    var locationText: String? {
        guard let path else { return nil }
        return line.map { "\(path):\($0)" } ?? path
    }

    /// "js/sql-injection (CodeQL)".
    var ruleText: String? {
        switch (rule, tool) {
        case let (rule?, tool?): "\(rule) (\(tool))"
        case let (rule?, nil): rule
        case let (nil, tool?): tool
        case (nil, nil): nil
        }
    }
}

extension GitHubAdvisory {
    /// "CVSS 9.1".
    var cvssText: String? {
        cvss.map { "CVSS \($0.score.formatted(.number.precision(.fractionLength(1))))" }
    }

    /// "CWE-79 Improper Neutralization …; CWE-80 …"; de namen komen van GitHub (Engels).
    var cweText: String? {
        cwes.isEmpty ? nil : cwes.map { "\($0.id) \($0.name)" }.joined(separator: "; ")
    }
}

extension GitHubAdvisory.AffectedPackage {
    /// "acme-web < 2.1.0 → 2.1.0".
    var line: String {
        var text = name
        if let vulnerableRange { text += " \(vulnerableRange)" }
        if let patched { text += " → \(patched)" }
        return text
    }
}

extension Vulnerability {
    /// "RUSTSEC-2026-0387 (RustSec), ook GHSA-… en CVE-…": de OSV-id met zijn database en de andere
    /// ids, ook die alleen GitHubs advies kent; `maxAliases` houdt een melding kort.
    func identifiers(_ advisory: GitHubAdvisory?, maxAliases: Int? = nil) -> String {
        sourceLine(adding: [advisory?.ghsaId, advisory?.cveId], maxAliases: maxAliases)
    }

    /// "Gemiddeld, CVSS 5.9": de ernst uit de beste bron (`severityAssessment`) en de CVSS-score;
    /// nil als geen bron er een geeft.
    func severityText(_ advisory: GitHubAdvisory?) -> String? {
        let assessment = severityAssessment(advisory)
        let level = assessment.level.map { String(localized: Vulnerability.severityLabel($0)) }
        let score = assessment.score.map { "CVSS \($0.formatted(.number.precision(.fractionLength(1))))" }
        let parts = [level, score].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

extension SecurityScan {
    /// Voor het klembord: per bron wat er is, of waarom niet.
    var clipboardLines: [String] {
        var lines: [String] = []
        for feed in feeds {
            let title = String(localized: feed.kind.title)
            switch feed.availability {
            case .available:
                switch feed.kind {
                case .codeScanning, .advancedSecurity:
                    lines.append("\(title): \(String(localized: "\(alerts.count) open meldingen"))")
                    for alert in alerts {
                        var line = "- [\(String(localized: alert.severityLabel))] \(alert.title)"
                        if let location = alert.locationText { line += ", \(location)" }
                        if let package = alert.package { line += ", \(package)" }
                        line += " (\(alert.url.absoluteString))"
                        lines.append(line)
                    }
                    if feed.kind == .advancedSecurity, let count = secretCount, count > 0 {
                        lines.append(String(localized: "\(count) open geheimen"))
                    }
                case .secretScanning:
                    lines.append("\(title): \(String(localized: "\(secretCount ?? 0) open geheimen"))")
                case .repositoryAdvisories:
                    lines.append("\(title): \(String(localized: "\(advisories.count) gepubliceerd"))")
                    for advisory in advisories {
                        var line = "- \(advisory.ghsaId)"
                        if let cve = advisory.cveId { line += ", \(cve)" }
                        let severity = [advisory.severity.map { String(localized: Vulnerability.severityLabel($0)) }, advisory.cvssText]
                            .compactMap { $0 }
                        if !severity.isEmpty { line += " [\(severity.joined(separator: ", "))]" }
                        if let summary = advisory.summary { line += ": \(summary)" }
                        line += " (\(advisory.url.absoluteString))"
                        lines.append(line)
                    }
                }
            case .needsPermission:
                lines.append("\(title): \(String(localized: "Toestemming nodig"))")
            case .notEnabled:
                lines.append("\(title): \(String(localized: "Staat uit"))")
            case .notAvailable:
                lines.append("\(title): \(String(localized: "Niet beschikbaar op deze server"))")
            case .failed:
                lines.append("\(title): \(feed.message ?? "")")
            }
        }
        return lines
    }
}
