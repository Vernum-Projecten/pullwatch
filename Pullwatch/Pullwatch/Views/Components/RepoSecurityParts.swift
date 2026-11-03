import PullwatchCore
import SwiftUI

/// De beveiligingsgegevens van de dienst zelf op de repo-pagina: code scanning, open geheimen en
/// eigen adviezen (GitHub), of Advanced Security (Azure DevOps). Wat uit staat of nog goedgekeurd
/// moet worden staat er stil bij, met een link.
struct RepoSecuritySection: View {
    let scan: SecurityScan
    let provider: ProviderKind

    /// Meer meldingen staan bij de dienst zelf.
    private static let maxAlerts = 10

    var body: some View {
        Section {
            ForEach(scan.feeds, id: \.kind) { feed in
                switch feed.availability {
                case .available:
                    available(feed)
                case .needsPermission:
                    LabeledContent {
                        HStack(spacing: 8) {
                            Text("Toestemming nodig").foregroundStyle(.secondary)
                            if let link = feed.link {
                                Link(provider == .gitHub ? "Goedkeuren" : "Tokens", destination: link)
                            }
                        }
                    } label: {
                        Text(feed.kind.title)
                    }
                    .help(provider == .gitHub
                          ? Text("De eigenaar moet het nieuwe recht van de Pullwatch-app goedkeuren bij de installatie op GitHub")
                          : Text("Het token mag Advanced Security niet lezen; geef het de scope Advanced Security (lezen)"))
                case .notEnabled:
                    LabeledContent {
                        Text("Staat uit").foregroundStyle(.secondary)
                    } label: {
                        Text(feed.kind.title)
                    }
                case .notAvailable:
                    LabeledContent {
                        Text("Niet beschikbaar op deze server").foregroundStyle(.secondary)
                    } label: {
                        Text(feed.kind.title)
                    }
                case .failed:
                    LabeledContent {
                        Text(verbatim: feed.message ?? "").foregroundStyle(.orange).lineLimit(2)
                    } label: {
                        Text(feed.kind.title)
                    }
                }
            }
        } header: {
            Text(provider == .gitHub ? "Beveiliging op GitHub" : "Advanced Security")
        }
    }

    @ViewBuilder
    private func available(_ feed: SecurityFeed) -> some View {
        switch feed.kind {
        case .codeScanning, .advancedSecurity:
            let alerts = scan.alerts
            LabeledContent {
                if let link = feed.link, !alerts.isEmpty {
                    Link("\(alerts.count) open meldingen", destination: link)
                } else {
                    Text(alerts.isEmpty ? "Geen open meldingen" : "\(alerts.count) open meldingen")
                        .foregroundStyle(.secondary)
                }
            } label: {
                Text(feed.kind.title)
            }
            ForEach(alerts.prefix(Self.maxAlerts)) { alert in
                SecurityAlertRow(alert: alert)
            }
            if feed.kind == .advancedSecurity, let count = scan.secretCount, count > 0 {
                LabeledContent {
                    Text("\(count) open geheimen").foregroundStyle(.red)
                } label: {
                    Text("Geheimen")
                }
            }
        case .secretScanning:
            LabeledContent {
                let count = scan.secretCount ?? 0
                if count > 0, let link = feed.link {
                    Link("\(count) open geheimen", destination: link)
                } else {
                    Text("Geen open geheimen").foregroundStyle(.secondary)
                }
            } label: {
                Text(feed.kind.title)
            }
        case .repositoryAdvisories:
            LabeledContent {
                if scan.advisories.isEmpty {
                    Text("Geen").foregroundStyle(.secondary)
                } else if let link = feed.link {
                    Link("\(scan.advisories.count) gepubliceerd", destination: link)
                }
            } label: {
                Text(feed.kind.title)
                Text("Wat dit project zelf over zijn lekken publiceert")
            }
            ForEach(scan.advisories) { advisory in
                OwnAdvisoryRow(advisory: advisory)
            }
        }
    }
}

/// Eén melding van code scanning of Advanced Security: ernst, titel (link naar de melding), plek
/// en regel.
private struct SecurityAlertRow: View {
    let alert: SecurityAlert

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Pill(text: alert.severityLabel, tint: alert.severityColor)
                Link(destination: alert.url) {
                    Text(verbatim: alert.title).lineLimit(1)
                }
                .help(Text(verbatim: alert.title))
            }
            HStack(spacing: 8) {
                if let location = alert.locationText {
                    Label(location, systemImage: "doc.text").labelStyle(.titleAndIcon)
                }
                if let package = alert.package {
                    Label(package, systemImage: "shippingbox").labelStyle(.titleAndIcon)
                }
                if let rule = alert.ruleText {
                    Text(verbatim: rule)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 1)
    }
}

/// Een eigen gepubliceerd advies van de repository.
private struct OwnAdvisoryRow: View {
    let advisory: GitHubAdvisory

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Pill(text: Vulnerability.severityLabel(advisory.severity), tint: Vulnerability.severityColor(advisory.severity))
                if let cvss = advisory.cvss {
                    Pill(text: "CVSS \(cvss.score.formatted(.number.precision(.fractionLength(1))))", tint: Vulnerability.severityColor(advisory.severity))
                        .help(Text(verbatim: cvss.vector ?? ""))
                }
                Link(advisory.ghsaId, destination: advisory.url)
                if let cve = advisory.cveId {
                    Text(verbatim: cve).foregroundStyle(.secondary)
                }
            }
            if let summary = advisory.summary {
                Text(verbatim: summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            ForEach(advisory.packages, id: \.self) { package in
                Text(verbatim: package.line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 1)
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

    var severityColor: Color {
        if severity != nil { return Vulnerability.severityColor(severity) }
        return toolSeverity == "error" ? .yellow : .gray
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
