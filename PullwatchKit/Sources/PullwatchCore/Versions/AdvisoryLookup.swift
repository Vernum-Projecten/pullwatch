import Foundation

extension VersionReport {
    /// Het advies van GitHub bij een eigen vondst: op GHSA-id, anders op CVE.
    public func advisory(for vulnerability: Vulnerability) -> GitHubAdvisory? {
        if let ghsa = vulnerability.ghsa, let advisory = advisories[ghsa] { return advisory }
        guard let cve = vulnerability.cve else { return nil }
        return advisories.values.filter { $0.cveId == cve }.min { $0.ghsaId < $1.ghsaId }
    }

    /// Alle kwetsbaarheden in het rapport, ook die van de laatste release.
    var allVulnerabilities: [Vulnerability] {
        repos.flatMap { $0.vulnerabilities + ($0.release?.vulnerabilities ?? []) }
    }

    /// Wat de volgende opzoeking moet vragen: GHSA-ids zonder (verse) gegevens, en CVE's van
    /// vondsten zonder GHSA-id waar nog geen advies bij gevonden is. Een eerdere misser wordt pas
    /// na `GitHubAdvisory.missRetryInterval` opnieuw gevraagd.
    public func missingAdvisoryLookups(now: Date) -> (ghsaIds: Set<String>, cves: Set<String>) {
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
    /// Met het token van het eerste GitHub-account (hogere rate limit), anders zonder.
    public func completingAdvisories(of report: VersionReport, accounts: [Account]) async -> VersionReport {
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
