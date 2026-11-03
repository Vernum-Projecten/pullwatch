import AppKit
import PullwatchCore
import SwiftUI

struct ComponentRow: View {
    let component: ComponentVersion
    /// Nieuwste tag en hetzelfde onderdeel daarin; nil als de repo geen tags heeft.
    let release: (tag: String, component: ComponentVersion?)?

    var body: some View {
        HStack(spacing: 6) {
            Text(component.label)
            Text(component.versionText).monospacedDigit().foregroundStyle(.secondary)
            VersionStatusPill(status: component.status)
            // Ter info, zonder status: wat op main al bijgewerkt is telt niet.
            if let release, let old = release.component, old.version != component.version {
                Text(verbatim: "· \(release.tag): \(old.version)").monospacedDigit().foregroundStyle(.tertiary)
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

struct VulnerabilityList: View {
    let repo: RepoVersions
    @State var isExpanded = false
    /// Klik op een package dat in Versies staat; nil laat het package als tekst staan.
    var showPackage: ((String) -> Void)? = nil
    var knownPackages: Set<String> = []


    private var vulnerabilities: [Vulnerability] { repo.vulnerabilities }

    private var title: String {
        let count = vulnerabilities.count
        let bySeverity = ["CRITICAL", "HIGH", "MODERATE", "LOW"].compactMap { severity -> String? in
            let n = vulnerabilities.filter { $0.severity == severity }.count
            return n > 0 ? "\(n) \(severity.lowercased())" : nil
        }
        let detail = bySeverity.isEmpty ? "" : " (\(bySeverity.joined(separator: ", ")))"
        var text = (count == 1 ? String(localized: "1 kwetsbaarheid") : String(localized: "\(count) kwetsbaarheden")) + detail
        if let release = repo.release, release.error == nil {
            let inRelease = vulnerabilities.filter { repo.isInRelease($0) == true }.count
            text += " · " + String(localized: "\(inRelease) ook in \(release.tag)", comment: "Aantal kwetsbaarheden, tagnaam")
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                    Label(title, systemImage: "exclamationmark.shield")
                        .foregroundStyle(VersionStatus.eol.color)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(vulnerabilities.enumerated()), id: \.offset) { _, vulnerability in
                        VulnerabilityRow(
                            vulnerability: vulnerability,
                            location: repo.location(of: vulnerability),
                            showPackage: knownPackages.contains(vulnerability.package) ? showPackage : nil
                        )
                    }
                }
                .padding(.leading, 16)
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
                SeverityPill(severity: vulnerability.severity)
                Link(vulnerability.cve ?? vulnerability.id, destination: vulnerability.url)
                if let showPackage {
                    Button(packageText) { showPackage(vulnerability.package) }
                        .buttonStyle(.link)
                        .monospacedDigit()
                        .help("Toon dit package in Versies, met alle repo's die het gebruiken")
                } else {
                    Text(packageText).monospacedDigit().foregroundStyle(.secondary)
                }
                if let location {
                    LocationPill(location: location)
                }
            }
            if let summary = vulnerability.summary {
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .help(Text(verbatim: "\(vulnerability.id) — \(vulnerability.source)"))
    }

    private var packageText: String {
        let base = "\(vulnerability.package) \(vulnerability.version)"
        return vulnerability.fixedIn.map { "\(base) → \($0)" } ?? base
    }
}

/// Of een kwetsbaarheid van main ook in de laatste release zit.
enum VulnerabilityLocation {
    case alsoInRelease(tag: String)
    case mainOnly

    var label: String {
        switch self {
        case .alsoInRelease(let tag): String(localized: "ook in \(tag)", comment: "Tagnaam")
        case .mainOnly: String(localized: "alleen main")
        }
    }

    var help: String {
        switch self {
        case .alsoInRelease(let tag): String(localized: "Zit ook in de laatste release (\(tag))", comment: "Tagnaam")
        case .mainOnly: String(localized: "Nieuw sinds de laatste release; nog niet uitgebracht")
        }
    }

    var color: Color {
        switch self {
        case .alsoInRelease: .red
        case .mainOnly: .orange
        }
    }
}

private struct LocationPill: View {
    let location: VulnerabilityLocation

    var body: some View {
        Text(location.label)
            .font(.caption2)
            .foregroundStyle(location.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(location.color.opacity(0.5)))
            .help(location.help)
    }
}

extension RepoVersions {
    /// nil als er geen release gecheckt is.
    func location(of vulnerability: Vulnerability) -> VulnerabilityLocation? {
        guard let release, let inRelease = isInRelease(vulnerability) else { return nil }
        return inRelease ? .alsoInRelease(tag: release.tag) : .mainOnly
    }
}

private struct SeverityPill: View {
    let severity: String?

    private var color: Color {
        switch severity {
        case "CRITICAL": .red
        case "HIGH": .orange
        case "MODERATE", "MEDIUM": .yellow
        default: .gray
        }
    }

    var body: some View {
        Text((severity ?? "?").capitalized)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
    }
}

extension RepoVersions {
    /// Platte tekst voor het klembord: repo, onderdelen en kwetsbaarheden.
    var clipboardText: String {
        var lines = [repo]
        if let error { lines.append(String(localized: "Fout: \(error)")) }
        for component in components {
            lines.append("\(component.label) \(component.versionText) (\(component.status.label))")
        }
        if let release {
            lines.append(String(localized: "Laatste tag \(release.tag):"))
            if let error = release.error { lines.append(String(localized: "Fout: \(error)")) }
            for component in release.components {
                lines.append("  \(component.label) \(component.versionText) (\(component.status.label))")
            }
        }
        if let vulnerabilityError { lines.append(vulnerabilityError) }
        if !vulnerabilities.isEmpty {
            lines.append(String(localized: "Kwetsbaarheden:"))
            for v in vulnerabilities {
                var line = "- \(v.cve ?? v.id)"
                if let location = location(of: v) { line += " {\(location.label)}" }
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

    var label: String {
        switch self {
        case .current: String(localized: "Actueel")
        case .behind: String(localized: "Achter")
        case .eol: String(localized: "EOL")
        case .unknown: String(localized: "Onbekend")
        }
    }
}

/// Kleine gekleurde pill met de versiestatus van een onderdeel.
struct VersionStatusPill: View {
    let status: VersionStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.bold())
            .foregroundStyle(status.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(status.color.opacity(0.15), in: Capsule())
    }
}
