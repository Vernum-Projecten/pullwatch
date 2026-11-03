import AppKit
import PullwatchCore
import SwiftUI

/// Eén taal of framework van een repo: versie, status en wat er in de laatste release stond.
struct ComponentRow: View {
    let component: ComponentVersion
    /// Nieuwste tag en hetzelfde onderdeel daarin; nil als de repo geen tags heeft.
    let release: (tag: String, component: ComponentVersion?)?

    var body: some View {
        HStack(spacing: 6) {
            Text(component.label)
            Text(verbatim: component.versionText).monospacedDigit().foregroundStyle(.secondary)
            Pill(text: component.status.label, tint: component.status.color)
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

/// De kwetsbaarheden van een repo, inklapbaar; met per stuk de ernst, het package en of het al
/// in de laatste release zat.
struct VulnerabilityList: View {
    let repo: RepoVersions
    /// Klik op een package dat in Versies staat; nil laat het package als tekst staan.
    var showPackage: ((String) -> Void)? = nil
    var knownPackages: Set<String> = []

    @State private var isExpanded = true

    /// Hoeveel er ook in de laatste release zitten, met die tag; nil zonder gecheckte release.
    private var inRelease: (count: Int, tag: String)? {
        guard let release = repo.release, release.error == nil else { return nil }
        return (repo.vulnerabilities.filter { repo.isInRelease($0) == true }.count, release.tag)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(repo.vulnerabilities, id: \.rowId) { vulnerability in
                VulnerabilityRow(
                    vulnerability: vulnerability,
                    location: repo.location(of: vulnerability),
                    showPackage: knownPackages.contains(vulnerability.package) ? showPackage : nil
                )
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Label("\(repo.vulnerabilities.count) kwetsbaarheden", systemImage: "exclamationmark.shield")
                    .foregroundStyle(VersionStatus.eol.color)
                if let inRelease {
                    Text("\(inRelease.count) ook in \(inRelease.tag)", comment: "Aantal kwetsbaarheden, tagnaam")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct VulnerabilityRow: View {
    let vulnerability: Vulnerability
    let location: VulnerabilityLocation?
    var showPackage: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Pill(text: Vulnerability.severityLabel(vulnerability.severity), tint: Vulnerability.severityColor(vulnerability.severity))
                Link(vulnerability.cve ?? vulnerability.id, destination: vulnerability.url)
                if let showPackage {
                    Button(packageText) { showPackage(vulnerability.package) }
                        .buttonStyle(.link)
                        .monospacedDigit()
                        .help("Toon dit package in Versies, met alle repo's die het gebruiken")
                } else {
                    Text(verbatim: packageText).monospacedDigit().foregroundStyle(.secondary)
                }
                if let location {
                    Pill(text: location.label, tint: location.color)
                        .help(Text(location.help))
                }
            }
            if let summary = vulnerability.summary {
                Text(verbatim: summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .help(Text(verbatim: "\(vulnerability.id)\n\(vulnerability.source)"))
    }

    private var packageText: String {
        let base = "\(vulnerability.package) \(vulnerability.version)"
        return vulnerability.fixedIn.map { "\(base) → \($0)" } ?? base
    }
}

extension Vulnerability {
    /// Vaste id voor lijsten: hetzelfde advies kan meerdere packages of versies raken.
    var rowId: String { "\(id) \(package) \(version)" }

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

    /// Platte tekst voor het klembord: repo, onderdelen en kwetsbaarheden.
    var clipboardText: String {
        var lines = [repo]
        if let error { lines.append(String(localized: "Fout: \(error)")) }
        for component in components {
            lines.append("\(component.label) \(component.versionText) (\(String(localized: component.status.label)))")
        }
        if let release {
            lines.append(String(localized: "Laatste tag \(release.tag):"))
            if let error = release.error { lines.append(String(localized: "Fout: \(error)")) }
            for component in release.components {
                lines.append("  \(component.label) \(component.versionText) (\(String(localized: component.status.label)))")
            }
        }
        if let vulnerabilityError { lines.append(vulnerabilityError) }
        if !vulnerabilities.isEmpty {
            lines.append(String(localized: "Kwetsbaarheden:"))
            for v in vulnerabilities {
                var line = "- \(v.cve ?? v.id)"
                if let location = location(of: v) { line += " {\(String(localized: location.label))}" }
                if let severity = v.severity { line += " [\(severity)]" }
                line += " \(v.package) \(v.version)"
                if let fixedIn = v.fixedIn { line += " → \(fixedIn)" }
                if let summary = v.summary { line += ": \(summary)" }
                line += " (\(v.url.absoluteString))"
                lines.append(line)
            }
        }
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
