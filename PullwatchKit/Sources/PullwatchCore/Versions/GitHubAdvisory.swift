import Foundation

/// Een advies uit de GitHub Advisory Database (`GET /advisories/{ghsa_id}`) of een eigen advies
/// van een repository (`GET /repos/{owner}/{repo}/security-advisories`): GitHubs eigen ernst,
/// CVSS, CWE's en de pagina op github.com.
public struct GitHubAdvisory: Codable, Hashable, Sendable, Identifiable {
    /// Bv. "GHSA-29mw-wpgm-hmr9".
    public let ghsaId: String
    public let cveId: String?
    public let summary: String?
    /// Zoals bij `Vulnerability`: "CRITICAL", "HIGH", "MODERATE" of "LOW"; nil als GitHub geen
    /// ernst geeft ("unknown").
    public let severity: String?
    /// De nieuwste CVSS-versie die GitHub heeft (v4 vóór v3).
    public let cvss: CVSS?
    public let cwes: [CWE]
    /// De pagina op github.com/advisories (globaal) of in de repository (eigen advies).
    public let url: URL
    public let publishedAt: Date?
    public let withdrawnAt: Date?
    /// Alleen bij een eigen advies van de repository: de geraakte packages.
    public let packages: [AffectedPackage]
    /// Wanneer Pullwatch dit advies ophaalde; na `refreshInterval` haalt de check het opnieuw.
    public let fetchedAt: Date

    public var id: String { ghsaId }

    public struct CVSS: Codable, Hashable, Sendable {
        /// 0 t/m 10.
        public let score: Double
        /// Bv. "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H".
        public let vector: String?

        public init(score: Double, vector: String?) {
            self.score = score
            self.vector = vector
        }

        /// "3.1" of "4.0" uit de vector; nil zonder vector.
        public var version: String? {
            guard let vector, vector.hasPrefix("CVSS:") else { return nil }
            return vector.dropFirst("CVSS:".count).split(separator: "/").first.map(String.init)
        }
    }

    public struct CWE: Codable, Hashable, Sendable {
        /// Bv. "CWE-79".
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public struct AffectedPackage: Codable, Hashable, Sendable {
        public let ecosystem: String
        public let name: String
        public let vulnerableRange: String?
        public let patched: String?

        public init(ecosystem: String, name: String, vulnerableRange: String?, patched: String?) {
            self.ecosystem = ecosystem
            self.name = name
            self.vulnerableRange = vulnerableRange
            self.patched = patched
        }
    }

    public init(
        ghsaId: String, cveId: String?, summary: String?, severity: String?, cvss: CVSS?, cwes: [CWE], url: URL,
        publishedAt: Date? = nil, withdrawnAt: Date? = nil, packages: [AffectedPackage] = [], fetchedAt: Date
    ) {
        self.ghsaId = ghsaId
        self.cveId = cveId
        self.summary = summary
        self.severity = severity
        self.cvss = cvss
        self.cwes = cwes
        self.url = url
        self.publishedAt = publishedAt
        self.withdrawnAt = withdrawnAt
        self.packages = packages
        self.fetchedAt = fetchedAt
    }

    /// Een advies verandert soms nog (CVSS, CWE, ingetrokken); na een maand haalt de check het opnieuw.
    public static let refreshInterval: TimeInterval = 30 * 24 * 3600
    /// Een id of CVE zonder advies bij GitHub wordt na een week opnieuw geprobeerd.
    public static let missRetryInterval: TimeInterval = 7 * 24 * 3600

    /// De pagina in de GitHub Advisory Database, ook voor een id zonder opgehaald advies.
    public static func pageURL(ghsaId: String) -> URL {
        URL(string: "https://github.com/advisories")!.appending(path: ghsaId)
    }

    /// GitHubs "medium" heet in de Advisory Database en bij OSV "moderate"; ook voor de
    /// `security_severity_level` van code scanning.
    public static func securitySeverity(_ raw: String?) -> String? {
        switch raw?.lowercased() {
        case "critical": "CRITICAL"
        case "high": "HIGH"
        case "medium", "moderate": "MODERATE"
        case "low": "LOW"
        default: nil
        }
    }
}

/// Het advies zoals de REST API het geeft; dezelfde vorm voor `/advisories` en
/// `/repos/{owner}/{repo}/security-advisories`, op `first_patched_version` en `patched_versions` na.
package struct AdvisoryDTO: Decodable, Sendable {
    package struct Score: Decodable, Sendable {
        let vectorString: String?
        let score: Double?
    }

    package struct Severities: Decodable, Sendable {
        let cvssV3: Score?
        let cvssV4: Score?
    }

    package struct CWE: Decodable, Sendable {
        let cweId: String
        let name: String?
    }

    package struct Vulnerability: Decodable, Sendable {
        struct Package: Decodable, Sendable {
            let ecosystem: String?
            let name: String?
        }
        let package: Package?
        let vulnerableVersionRange: String?
        let firstPatchedVersion: String?
        let patchedVersions: String?
    }

    let ghsaId: String
    let cveId: String?
    let htmlUrl: String?
    let summary: String?
    let severity: String?
    let cvssSeverities: Severities?
    /// Ouder veld, nog in sommige antwoorden.
    let cvss: Score?
    let cwes: [CWE]?
    let publishedAt: String?
    let withdrawnAt: String?
    let vulnerabilities: [Vulnerability]?

    package func advisory(fetchedAt: Date, withPackages: Bool = false) -> GitHubAdvisory {
        let score = [cvssSeverities?.cvssV4, cvssSeverities?.cvssV3, cvss].compactMap { $0 }
            .first { ($0.score ?? 0) > 0 }
        return GitHubAdvisory(
            ghsaId: ghsaId,
            cveId: cveId,
            summary: summary,
            severity: GitHubAdvisory.securitySeverity(severity),
            cvss: score.flatMap { s in s.score.map { GitHubAdvisory.CVSS(score: $0, vector: s.vectorString) } },
            cwes: (cwes ?? []).map { GitHubAdvisory.CWE(id: $0.cweId, name: $0.name ?? $0.cweId) },
            url: htmlUrl.flatMap(URL.init(string:)) ?? GitHubAdvisory.pageURL(ghsaId: ghsaId),
            publishedAt: publishedAt.flatMap(DateParsing.parse),
            withdrawnAt: withdrawnAt.flatMap(DateParsing.parse),
            packages: withPackages ? (vulnerabilities ?? []).compactMap { item in
                guard let name = item.package?.name else { return nil }
                return GitHubAdvisory.AffectedPackage(
                    ecosystem: item.package?.ecosystem ?? "",
                    name: name,
                    vulnerableRange: item.vulnerableVersionRange,
                    patched: item.patchedVersions ?? item.firstPatchedVersion
                )
            } : [],
            fetchedAt: fetchedAt
        )
    }
}

/// De openbare GitHub Advisory Database: geen extra rechten nodig, met een token van GitHub
/// (als er een is) voor de hogere rate limit.
public enum AdvisoryDatabase {
    static let apiBase = URL(string: "https://api.github.com")!
    static let concurrency = 4

    public struct Lookup: Sendable, Equatable {
        public var advisories: [GitHubAdvisory] = []
        /// GHSA-ids en CVE's waar GitHub geen advies voor heeft.
        public var misses: [String] = []
        /// Opzoekingen die mislukten (netwerk, rate limit); de volgende check probeert ze opnieuw.
        public var failed = 0
    }

    /// Haalt elk GHSA-id en elke CVE (zonder bekend GHSA-id) één keer op, hooguit `concurrency` tegelijk.
    public static func lookUp(
        ghsaIds: Set<String>, cves: Set<String>, http: any HTTPClient, token: String?, now: Date
    ) async -> Lookup {
        let work = ghsaIds.sorted().map { (key: $0, isCVE: false) } + cves.sorted().map { (key: $0, isCVE: true) }
        return await withTaskGroup(of: (key: String, result: Result<GitHubAdvisory?, any Error>).self) { group in
            var pending = work.makeIterator()
            func addNext() {
                guard let item = pending.next() else { return }
                group.addTask {
                    do {
                        let found = item.isCVE
                            ? try await advisory(cve: item.key, http: http, token: token, now: now)
                            : try await advisory(ghsaId: item.key, http: http, token: token, now: now)
                        return (item.key, .success(found))
                    } catch {
                        return (item.key, .failure(error))
                    }
                }
            }
            for _ in 0..<concurrency { addNext() }
            var lookup = Lookup()
            for await (key, result) in group {
                switch result {
                case .success(let advisory?): lookup.advisories.append(advisory)
                case .success(nil): lookup.misses.append(key)
                case .failure: lookup.failed += 1
                }
                addNext()
            }
            lookup.advisories.sort { $0.ghsaId < $1.ghsaId }
            lookup.misses.sort()
            return lookup
        }
    }

    /// `GET /advisories/{ghsa_id}`; nil bij een 404.
    public static func advisory(ghsaId: String, http: any HTTPClient, token: String?, now: Date) async throws -> GitHubAdvisory? {
        do {
            let data = try await get(apiBase.appending(path: "advisories").appending(path: ghsaId), query: [], http: http, token: token, now: now)
            return try JSONDecoding.decode(AdvisoryDTO.self, from: data, snakeCase: true).advisory(fetchedAt: now)
        } catch ProviderError.server(status: 404) {
            return nil
        }
    }

    /// `GET /advisories?cve_id=`: het eerste nagekeken advies met die CVE; nil als er geen is.
    public static func advisory(cve: String, http: any HTTPClient, token: String?, now: Date) async throws -> GitHubAdvisory? {
        let data = try await get(
            apiBase.appending(path: "advisories"),
            query: [URLQueryItem(name: "cve_id", value: cve), URLQueryItem(name: "per_page", value: "5")],
            http: http, token: token, now: now
        )
        return try JSONDecoding.decode([AdvisoryDTO].self, from: data, snakeCase: true).first?.advisory(fetchedAt: now)
    }

    private static func get(_ url: URL, query: [URLQueryItem], http: any HTTPClient, token: String?, now: Date) async throws -> Data {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await http.send(request)
        try HTTPStatus.check(response, now: now)
        return data
    }
}
