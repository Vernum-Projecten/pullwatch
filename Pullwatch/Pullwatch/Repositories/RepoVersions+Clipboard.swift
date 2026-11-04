import AppKit
import PullwatchCore
import SwiftUI

extension RepoVersions {
    /// nil als er geen release gecheckt is.
    func location(of vulnerability: Vulnerability) -> VulnerabilityLocation? {
        guard let release, let inRelease = isInRelease(vulnerability) else { return nil }
        return inRelease ? .alsoInRelease(tag: release.tag) : .mainOnly
    }

    /// Platte tekst voor het klembord: repo, onderdelen, packages per workspace, kwetsbaarheden
    /// per advies (id met database en alle andere ids, ernst met CVSS en waar die vandaan komt,
    /// CWE's, de fix-links), met waar en hoe elke install erin komt, de ingetrokken adviezen, en
    /// de beveiligingsmeldingen van de dienst. Wat niet gecontroleerd is omdat een bron uit stond,
    /// staat er met de vaste zin; `advisoryDetailsOff`: de GitHub Advisory Database staat uit, dus
    /// er zijn geen details van GitHub.
    func clipboardText(
        advisories gitHub: [String: GitHubAdvisory] = [:], report: VersionReport? = nil, advisoryDetailsOff: Bool = false
    ) -> String {
        let context = report?.updateContext(for: self) ?? .empty
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
                let id = DataSourceID.releases(product: component.product)
                let status = release.isUnchecked(id) ? SourceOff.notChecked(id) : String(localized: component.status.label)
                lines.append("  \(component.label) \(component.versionText) (\(status))")
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
        // Wat niet gecontroleerd is omdat een bron uit stond (een releasebron staat al bij het onderdeel).
        for source in skippedInOrder where source != .endOfLife && source != .swiftOrg {
            lines.append(SourceOff.versionsText(source))
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
