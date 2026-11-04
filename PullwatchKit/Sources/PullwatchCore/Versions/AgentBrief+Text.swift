import Foundation

extension AgentBrief {
    // MARK: - Zinnen

    /// De opdracht als een kopje niets te doen geeft.
    static let nothingToDo = "nothing to fix in this section."

    /// "2 open secrets (<link>)"; de link alleen als er iets open staat.
    static func secretsText(_ count: Int, link: URL?) -> String {
        let text = "\(count) open \(count == 1 ? "secret" : "secrets")"
        guard count > 0, let link else { return text }
        return "\(text) (\(link.absoluteString))"
    }

    /// Waarom de nieuwste versie niet zomaar kan; nil als niets tegenhoudt (binnen het bereik,
    /// actueel of onbekend).
    package static func blockerSentence(package: String, installed: String, requested: String?, update: PackageUpdate) -> String? {
        let latest = update.latest ?? "the latest version"
        let sentence: String
        switch update.status {
        case .needsManifestChange:
            let range = requested ?? "the requested range"
            sentence = update.step == .major
                ? "\(package) \(latest) needs a new major version (outside \(range))."
                : "\(package) \(latest) is outside the requested range \(range)."
        case .blockedByPackage(let parent, let range, let minimum):
            let next = minimum.map { "update \(parent) to \($0) first" } ?? "no known version of \(parent) allows it yet"
            sentence = "\(package) \(latest) is held back by \(parent), which asks for \(package) \(range); \(next)."
        case .blockedByPeer(let name, let needs, let installed):
            sentence = "\(package) \(latest) needs \(name) \(needs), the workspace has \(installed)."
        case .blockedByRuntime(let runtime, let needs, let installed):
            sentence = "\(package) \(latest) needs \(runtime) \(needs), the repo uses \(installed)."
        case .upToDate, .withinRange, .unknown:
            return nil
        }
        if let usable = update.usable, usable != installed, usable != update.latest {
            return sentence + " The newest version that works now is \(usable)."
        }
        return sentence
    }

    /// Wat bijgewerkt moet worden, als zin (zoals `VulnerabilityFix.text` in de app, in het Engels).
    package static func fixText(_ fix: VulnerabilityFix) -> String {
        switch fix {
        case .update(let package, let version): "Update \(package) to \(version)."
        case .withinRange(let package, let version): "Update \(package) to \(version) (within the requested range)."
        case .needsManifestChange(let package, let version): "Update \(package) to \(version); this needs a new requested range in the manifest."
        case .blocked(let package, let version, .package(let parent, _, let minimum?)): "Update \(parent) to \(minimum), so it allows \(package) \(version)."
        case .blocked(let package, let version, .package(let parent, _, nil)): "Update \(parent) so it pulls in \(package) \(version) or newer."
        case .blocked(let package, let version, .peer(let name, let needs, let installed)):
            "Update \(package) to \(version); it needs \(name) \(needs), the workspace has \(installed)."
        case .blocked(let package, let version, .runtime(let runtime, let needs, let installed)):
            "Update \(package) to \(version); it needs \(runtime) \(needs), the repo uses \(installed)."
        case .updateParent(let parent, let package, let minimum): "Update \(parent) so it pulls in \(package) \(minimum) or newer."
        case .none: "No fixed version is known yet."
        }
    }

    /// Zit het advies ook in de laatste release: "yes", "no", of "unknown" zonder antwoord.
    static func releaseCell(_ inRelease: Bool?) -> String {
        switch inRelease {
        case true?: "yes"
        case false?: "no"
        case nil: "unknown"
        }
    }

    static func statusText(_ status: VersionStatus) -> String {
        switch status {
        case .current: "current"
        case .behind: "behind"
        case .eol: "end of life"
        case .unknown: "unknown"
        }
    }

    /// "critical", "high", "moderate", "low" of "unknown".
    package static func severityName(_ severity: String?) -> String {
        switch severity {
        case "CRITICAL": "critical"
        case "HIGH": "high"
        case "MODERATE", "MEDIUM": "moderate"
        case "LOW": "low"
        default: "unknown"
        }
    }

    /// GitHubs ernst (anders die van OSV), met de CVSS-score als GitHub die geeft.
    static func severityText(_ vulnerability: Vulnerability, _ gitHub: GitHubAdvisory?) -> String {
        let level = severityName(gitHub?.severity ?? vulnerability.severity)
        guard let cvss = gitHub?.cvss else { return level }
        return "\(level) (CVSS \(String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), cvss.score)))"
    }

    /// De CVE (of het OSV-id) en het GHSA-id als dat anders is.
    static func identifiers(_ vulnerability: Vulnerability, _ gitHub: GitHubAdvisory?) -> String {
        let primary = vulnerability.cve ?? gitHub?.cveId ?? vulnerability.id
        guard let ghsa = vulnerability.ghsa ?? gitHub?.ghsaId, ghsa != primary else { return primary }
        return "\(primary), \(ghsa)"
    }

    /// "root, direct", "packages/web, via express → body-parser", met ", dev only" voor dev.
    static func whereText(_ vulnerability: Vulnerability) -> String {
        let how: String
        switch vulnerability.scope {
        case .direct: how = "direct"
        case .transitive where !vulnerability.via.isEmpty: how = "via \(vulnerability.via.joined(separator: " → "))"
        case .transitive: how = "transitive"
        case .unknown: how = "origin unknown"
        }
        let place = vulnerability.workspace.isEmpty ? "root" : vulnerability.workspace
        return "\(place), \(how)" + (vulnerability.kind == .dev ? ", dev only" : "")
    }

    static func feedTitle(_ kind: SecurityFeed.Kind) -> String {
        switch kind {
        case .codeScanning: "Code scanning"
        case .secretScanning: "Secret scanning"
        case .repositoryAdvisories: "Repository advisories"
        case .advancedSecurity: "Advanced Security alerts"
        }
    }

    static func alertRow(_ alert: SecurityAlert) -> [String] {
        let severity = alert.severity.map(severityName) ?? alert.toolSeverity ?? "unknown"
        let rule: String = switch (alert.rule, alert.tool) {
        case let (rule?, tool?): "\(rule) (\(tool))"
        case let (rule?, nil): rule
        case let (nil, tool?): tool
        case (nil, nil): "-"
        }
        let file = alert.path.map { path in alert.line.map { "\(path):\($0)" } ?? path } ?? alert.package.map { "package \($0)" } ?? "-"
        return [severity, rule, alert.title, file, alert.url.absoluteString]
    }

    // MARK: - Markdown

    /// Een tabelcel: `|` geëscaped, regeleinden als spatie, leeg als "-".
    static func cell(_ text: String) -> String {
        let flat = text.replacing("|", with: "\\|").replacing(/\r\n|\n|\r/, with: " ")
        return flat.isEmpty ? "-" : flat
    }

    static func table(_ columns: [String], _ rows: [[String]]) -> String {
        let line = { (cells: [String]) in "| " + cells.map(cell).joined(separator: " | ") + " |" }
        return ([line(columns), "|" + String(repeating: "---|", count: columns.count)] + rows.map(line)).joined(separator: "\n")
    }

    static func blockerBlock(_ blockers: [String]) -> String {
        switch blockers.count {
        case 0: "Blockers: none known."
        case 1: "Blockers: \(blockers[0])"
        default: (["Blockers:"] + blockers.map { "- \($0)" }).joined(separator: "\n")
        }
    }

    /// De datum als yyyy-MM-dd in `timeZone`.
    static func day(_ date: Date, in timeZone: TimeZone) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
    }

    /// De Engelse naam van een bron (de vertaalde naam van een omschrijving, zoals "GitHub security").
    package static func englishName(_ id: DataSourceID) -> String {
        DataSource.source(id).name(bundle: SourcesOverview.bundle(for: Locale(identifier: "en")))
    }

    static func unique(_ values: [String]) -> [String] {
        values.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
}
