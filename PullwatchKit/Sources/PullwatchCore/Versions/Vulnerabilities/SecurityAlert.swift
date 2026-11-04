public import Foundation

/// Eén open melding van de beveiligingsscans van de dienst zelf: code scanning van GitHub, of
/// Advanced Security van Azure DevOps (code en dependencies). Geheimen worden alleen geteld.
public struct SecurityAlert: Codable, Hashable, Sendable, Identifiable {
    public enum Source: String, Codable, Sendable {
        /// GitHub code scanning (CodeQL en andere tools).
        case codeScanning
        /// Azure DevOps Advanced Security.
        case advancedSecurity
    }

    public enum Kind: String, Codable, Sendable {
        case code
        case dependency
    }

    public let source: Source
    public let kind: Kind
    /// Nummer (GitHub) of alert-id (Azure DevOps); uniek binnen de repo en bron.
    public let number: Int
    public let title: String
    /// Id van de regel, bv. "js/sql-injection".
    public let rule: String?
    public let tool: String?
    /// Beveiligingsernst zoals bij `Vulnerability`: "CRITICAL", "HIGH", "MODERATE" of "LOW".
    public let severity: String?
    /// Ernst van de tool zelf als er geen beveiligingsernst is: "error", "warning" of "note".
    public let toolSeverity: String?
    /// Bestand en regel van de laatste vondst op de default branch.
    public let path: String?
    public let line: Int?
    /// Alleen bij een dependency-melding van Advanced Security.
    public let package: String?
    public let url: URL
    public let createdAt: Date?

    public var id: String { "\(source.rawValue)|\(number)" }

    public init(
        source: Source, kind: Kind, number: Int, title: String, rule: String? = nil, tool: String? = nil,
        severity: String?, toolSeverity: String? = nil, path: String? = nil, line: Int? = nil,
        package: String? = nil, url: URL, createdAt: Date? = nil
    ) {
        self.source = source
        self.kind = kind
        self.number = number
        self.title = title
        self.rule = rule
        self.tool = tool
        self.severity = severity
        self.toolSeverity = toolSeverity
        self.path = path
        self.line = line
        self.package = package
        self.url = url
        self.createdAt = createdAt
    }

    /// Hoe erg, zoals `Vulnerability.severityRank`: critical 4 … low 1. Zonder beveiligingsernst
    /// telt een "error" van de tool als medium en de rest als low.
    public var severityRank: Int {
        switch severity {
        case "CRITICAL": return 4
        case "HIGH": return 3
        case "MODERATE": return 2
        case "LOW": return 1
        default:
            switch toolSeverity {
            case "error": return 2
            case "warning", "note": return 1
            default: return 0
            }
        }
    }

    /// Critical of high: telt mee in de gezondheid van de repo en geeft (als dat aan staat) een melding.
    var isSerious: Bool { severityRank >= 3 }

    /// Ernstigste eerst, dan het nieuwste.
    static func sorted(_ alerts: [SecurityAlert]) -> [SecurityAlert] {
        alerts.sorted {
            if $0.severityRank != $1.severityRank { return $0.severityRank > $1.severityRank }
            return ($0.createdAt ?? .distantPast, $0.number) > ($1.createdAt ?? .distantPast, $1.number)
        }
    }
}

/// Wat Pullwatch van één soort beveiligingsgegevens van de dienst kon lezen.
public struct SecurityFeed: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// GitHub code scanning.
        case codeScanning
        /// GitHub secret scanning (alleen het aantal).
        case secretScanning
        /// Eigen gepubliceerde adviezen van de GitHub-repository.
        case repositoryAdvisories
        /// Azure DevOps Advanced Security (code, dependencies en geheimen).
        case advancedSecurity
    }

    public enum Availability: String, Codable, Sendable {
        case available
        /// Staat niet aan voor deze repo (404, of 403 omdat de functie uit staat).
        case notEnabled
        /// De GitHub App of het token mag het niet lezen; de eigenaar moet het recht goedkeuren.
        case needsPermission
        /// Bestaat niet op deze server (bijvoorbeeld de eigen adviezen op GitHub Enterprise Server).
        case notAvailable
        /// Netwerk, rate limit of een ander antwoord; de volgende check probeert het opnieuw.
        case failed
    }

    public let kind: Kind
    public let availability: Availability
    /// Waar je het aanzet of goedkeurt (`needsPermission`, `notEnabled`), of de lijst bij de dienst.
    public let link: URL?
    /// Foutmelding bij `failed`.
    public let message: String?

    public init(kind: Kind, availability: Availability, link: URL? = nil, message: String? = nil) {
        self.kind = kind
        self.availability = availability
        self.link = link
        self.message = message
    }
}

/// Beveiligingsgegevens van de dienst voor één repo, opgehaald met de versiecheck (eens per dag en
/// met "Check"), niet bij elke poll.
public struct SecurityScan: Codable, Hashable, Sendable {
    public let feeds: [SecurityFeed]
    /// Open meldingen van code scanning of Advanced Security, ernstigste eerst.
    public let alerts: [SecurityAlert]
    /// Aantal open geheimen; nil als secret scanning niet te lezen was.
    public let secretCount: Int?
    /// Eigen gepubliceerde adviezen van de repository, nieuwste eerst.
    public let advisories: [GitHubAdvisory]

    public init(feeds: [SecurityFeed], alerts: [SecurityAlert] = [], secretCount: Int? = nil, advisories: [GitHubAdvisory] = []) {
        self.feeds = feeds
        self.alerts = SecurityAlert.sorted(alerts)
        self.secretCount = secretCount
        self.advisories = advisories.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    public func feed(_ kind: SecurityFeed.Kind) -> SecurityFeed? {
        feeds.first { $0.kind == kind }
    }

    func isAvailable(_ kind: SecurityFeed.Kind) -> Bool {
        feed(kind)?.availability == .available
    }

    /// Critical en high, voor de bevindingen en de gezondheid in Repo's.
    var seriousAlerts: [SecurityAlert] { alerts.filter(\.isSerious) }

    /// Iets om te laten zien: meldingen, geheimen of eigen adviezen.
    var hasFindings: Bool { !alerts.isEmpty || (secretCount ?? 0) > 0 || !advisories.isEmpty }
}

extension VersionReport {
    /// Nieuwe open critical- en high-meldingen per repo ten opzichte van `previous`. Alleen voor
    /// een repo waarvan die bron toen ook te lezen was: anders komt bij de eerste check, of zodra
    /// een eigenaar het recht goedkeurt, een stortvloed aan meldingen.
    public func newSecurityAlerts(since previous: VersionReport?) -> [(repo: String, alert: SecurityAlert)] {
        guard let previous else { return [] }
        let before = Dictionary(previous.repos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [(repo: String, alert: SecurityAlert)] = []
        for repo in repos {
            guard let scan = repo.security, let old = before[repo.id]?.security else { continue }
            let known = Set(old.alerts.map(\.id))
            for alert in scan.seriousAlerts where !known.contains(alert.id) {
                let feed: SecurityFeed.Kind = alert.source == .codeScanning ? .codeScanning : .advancedSecurity
                guard old.isAvailable(feed) else { continue }
                result.append((repo.repo, alert))
            }
        }
        return result
    }
}
