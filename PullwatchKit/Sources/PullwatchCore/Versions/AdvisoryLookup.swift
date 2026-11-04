import Foundation

extension VersionReport {
    /// Het advies van GitHub bij een eigen vondst: op GHSA-id, anders op CVE.
    public func advisory(for vulnerability: Vulnerability) -> GitHubAdvisory? {
        if let ghsa = vulnerability.ghsa, let advisory = advisories[ghsa] { return advisory }
        guard let cve = vulnerability.cve else { return nil }
        return advisories.values.filter { $0.cveId == cve }.min { $0.ghsaId < $1.ghsaId }
    }

    /// De ernst van een eigen vondst uit de beste bron (`Vulnerability.severityAssessment(_:)`).
    public func severityAssessment(for vulnerability: Vulnerability) -> SeverityAssessment {
        vulnerability.severityAssessment(advisory(for: vulnerability))
    }

    /// Alle kwetsbaarheden in het rapport, ook die van de laatste release.
    var allVulnerabilities: [Vulnerability] {
        repos.flatMap { $0.vulnerabilities + ($0.release?.vulnerabilities ?? []) }
    }

    /// Wat de volgende opzoeking moet vragen: GHSA-ids zonder (verse) gegevens, en CVE's van
    /// vondsten zonder GHSA-id waar nog geen advies bij gevonden is. Een eerdere misser wordt pas
    /// na `GitHubAdvisory.missRetryInterval` opnieuw gevraagd.
    func missingAdvisoryLookups(now: Date) -> (ghsaIds: Set<String>, cves: Set<String>) {
        func due(_ key: String) -> Bool {
            advisoryMisses[key].map { now.timeIntervalSince($0) >= GitHubAdvisory.missRetryInterval } ?? true
        }
        let knownCVEs = Set(advisories.values.compactMap(\.cveId))
        var ghsaIds: Set<String> = []
        var cves: Set<String> = []
        for vulnerability in allVulnerabilities {
            if let ghsa = vulnerability.ghsa {
                let stale = advisories[ghsa].map { now.timeIntervalSince($0.fetchedAt) >= GitHubAdvisory.refreshInterval }
                if stale ?? due(ghsa) { ghsaIds.insert(ghsa) }
            } else if let cve = vulnerability.cve, !knownCVEs.contains(cve), due(cve) {
                cves.insert(cve)
            }
        }
        return (ghsaIds, cves)
    }

    /// Neemt de adviezen en missers van `previous` over (een volledige check begint zonder).
    public func carryingAdvisories(from previous: VersionReport?) -> VersionReport {
        guard let previous else { return self }
        return VersionReport(
            checkedAt: checkedAt, repos: repos, latestPackages: latestPackages,
            advisories: previous.advisories.merging(advisories) { _, new in new },
            advisoryMisses: previous.advisoryMisses.merging(advisoryMisses) { _, new in new },
            packageMetadata: packageMetadata
        )
    }

    /// Voegt een opzoeking toe en laat weg waar geen repo meer naar verwijst.
    public func adding(_ lookup: AdvisoryDatabase.Lookup, at now: Date) -> VersionReport {
        var advisories = advisories
        var misses = advisoryMisses
        for advisory in lookup.advisories {
            advisories[advisory.ghsaId] = advisory
            misses[advisory.ghsaId] = nil
            if let cve = advisory.cveId { misses[cve] = nil }
        }
        for key in lookup.misses { misses[key] = now }
        let vulnerabilities = allVulnerabilities
        let usedGHSA = Set(vulnerabilities.compactMap(\.ghsa))
        let usedCVEs = Set(vulnerabilities.compactMap(\.cve))
        advisories = advisories.filter { usedGHSA.contains($0.key) || $0.value.cveId.map(usedCVEs.contains) == true }
        misses = misses.filter { usedGHSA.contains($0.key) || usedCVEs.contains($0.key) }
        return VersionReport(
            checkedAt: checkedAt, repos: repos, latestPackages: latestPackages, advisories: advisories, advisoryMisses: misses,
            packageMetadata: packageMetadata
        )
    }
}

extension VersionChecker {
    /// Haalt de GitHub-adviezen op die `report` nog mist, elk GHSA-id één keer voor alle repo's.
    /// Met het token van het eerste GitHub-account (hogere rate limit), anders zonder. Staat de
    /// GitHub Advisory Database uit, dan blijft `report` zoals het is.
    public func completingAdvisories(of report: VersionReport, accounts: [Account]) async -> VersionReport {
        guard isEnabled(.gitHubAdvisoryDatabase) else { return report }
        let date = now()
        let missing = report.missingAdvisoryLookups(now: date)
        guard !missing.ghsaIds.isEmpty || !missing.cves.isEmpty else { return report }
        var token: String?
        for account in accounts where account.kind == .gitHub {
            token = await makeProvider(account).advisoryDatabaseToken()
            if token != nil { break }
        }
        let lookup = await AdvisoryDatabase.lookUp(ghsaIds: missing.ghsaIds, cves: missing.cves, http: http, token: token, now: date)
        return report.adding(lookup, at: date)
    }
}

/// De ernst van een kwetsbaarheid uit de beste bron, met waar die vandaan komt.
public struct SeverityAssessment: Hashable, Sendable {
    public enum Origin: Hashable, Sendable {
        /// Uitgerekend uit de CVSS-vector van het OSV-record `record` (`id` of een alias).
        case cvss(CVSSRating, record: String)
        /// `database_specific.severity` van het OSV-record `record`.
        case database(record: String)
        /// GitHubs advies uit de Advisory Database (#73), via het GHSA-id of de CVE.
        case gitHub(ghsaId: String)
    }

    /// "CRITICAL", "HIGH", "MODERATE" of "LOW"; nil als geen bron een ernst geeft.
    public let level: String?
    /// 0.0 t/m 10.0; nil zonder CVSS.
    public let score: Double?
    public let vector: String?
    /// nil als geen bron een ernst geeft.
    public let origin: Origin?

    public init(level: String?, score: Double? = nil, vector: String? = nil, origin: Origin?) {
        self.level = level
        self.score = score
        self.vector = vector
        self.origin = origin
    }
}

extension Vulnerability {
    /// De ernst uit de beste bron: de CVSS-vector in OSV (de score rekent Pullwatch zelf uit),
    /// anders `database_specific.severity` van OSV, anders GitHubs advies bij het GHSA-alias.
    /// RustSec en Go geven vaak alleen een id; dan komt de ernst van GitHub.
    public func severityAssessment(_ advisory: GitHubAdvisory?) -> SeverityAssessment {
        let record = severityFrom ?? id
        if let cvss {
            return SeverityAssessment(level: cvss.level, score: cvss.score, vector: cvss.vector, origin: .cvss(cvss, record: record))
        }
        if let severity {
            return SeverityAssessment(level: severity, origin: .database(record: record))
        }
        if let advisory, advisory.severity != nil || advisory.cvss != nil {
            return SeverityAssessment(
                level: advisory.severity ?? advisory.cvss.flatMap { CVSSCalculator.rating($0.score) },
                score: advisory.cvss?.score,
                vector: advisory.cvss?.vector,
                origin: .gitHub(ghsaId: advisory.ghsaId)
            )
        }
        return SeverityAssessment(level: nil, origin: nil)
    }
}
