public import Foundation

/// De database die een OSV-record publiceert (de "home database" uit het OSV-schema). OSV.dev
/// verzamelt ze; het voorvoegsel van de id zegt waar het record vandaan komt
/// (ossf.github.io/osv-schema, "Defined database prefixes"). npm, NuGet, RubyGems, Packagist en
/// Maven hebben geen eigen database bij OSV: hun records zijn GHSA's van GitHub.
public enum AdvisorySource: String, Codable, Hashable, Sendable, CaseIterable {
    case gitHub
    case rustSec
    case pyPA
    case psf
    case go
    case rubySec
    case friendsOfPHP
    case nvd
    case malicious
    case ossFuzz
    case android
    case bitnami
    case chainguard
    case curl
    case debian
    case drupal
    case erlang
    case haskell
    case julia
    case ocaml
    case kubernetes
    case rConsortium
    case homebrew
    case redHat
    case suse
    case ubuntu
    case almaLinux
    case rockyLinux
    case alpine
    case gsd
    /// Een database die Pullwatch (nog) niet kent; OSV.dev heeft het record wel.
    case other

    /// Een onbekende waarde uit een nieuwere versions.json wordt `other`.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AdvisorySource(rawValue: raw) ?? .other
    }

    /// Voorvoegsel van de id (hoofdletters, tot het eerste streepje) → database.
    static let prefixes: [String: AdvisorySource] = [
        "GHSA": .gitHub,
        "RUSTSEC": .rustSec,
        "PYSEC": .pyPA,
        "PSF": .psf,
        "GO": .go,
        "RUBYSEC": .rubySec,
        "PHPSEC": .friendsOfPHP,
        "CVE": .nvd,
        "MAL": .malicious,
        "OSV": .ossFuzz,
        "ASB": .android, "PUB": .android,
        "BIT": .bitnami,
        "CGA": .chainguard,
        "CURL": .curl,
        "DEBIAN": .debian, "DSA": .debian, "DLA": .debian, "DTSA": .debian,
        "DRUPAL": .drupal,
        "EEF": .erlang,
        "HSEC": .haskell,
        "JLSEC": .julia,
        "OSEC": .ocaml,
        "KUBE": .kubernetes,
        "RSEC": .rConsortium,
        "BREW": .homebrew,
        "RHSA": .redHat, "RHBA": .redHat, "RHEA": .redHat,
        "SUSE": .suse, "OPENSUSE": .suse,
        "UBUNTU": .ubuntu, "USN": .ubuntu, "LSN": .ubuntu,
        "ALSA": .almaLinux, "ALBA": .almaLinux, "ALEA": .almaLinux,
        "RLSA": .rockyLinux, "RXSA": .rockyLinux,
        "ALPINE": .alpine,
        "GSD": .gsd,
    ]

    /// De database van een id uit zijn voorvoegsel; nil als het voorvoegsel onbekend is.
    public static func of(id: String) -> AdvisorySource? {
        guard let prefix = id.split(separator: "-").first else { return nil }
        return prefixes[prefix.uppercased()]
    }

    /// De database uit een bron-URL van het record (`affected[].database_specific.source` of
    /// `database_specific.url`), voor een id zonder bekend voorvoegsel.
    public static func of(sourceURL: String) -> AdvisorySource? {
        let url = sourceURL.lowercased()
        let known: [(String, AdvisorySource)] = [
            ("github/advisory-database", .gitHub),
            ("rustsec/advisory-db", .rustSec),
            ("pypa/advisory-database", .pyPA),
            ("vuln.go.dev", .go), ("pkg.go.dev/vuln", .go),
            ("rubysec/ruby-advisory-db", .rubySec),
            ("friendsofphp/security-advisories", .friendsOfPHP),
            ("ossf/malicious-packages", .malicious),
            ("cve-osv-conversion", .nvd), ("cvelistv5", .nvd),
        ]
        return known.first { url.contains($0.0) }?.1
    }

    /// Korte naam voor een label in een rij, de copy-tekst en een melding.
    public var label: String {
        switch self {
        case .gitHub: "GitHub"
        case .rustSec: "RustSec"
        case .pyPA: "PyPA"
        case .psf: "PSF"
        case .go: "Go"
        case .rubySec: "RubySec"
        case .friendsOfPHP: "FriendsOfPHP"
        case .nvd: "NVD"
        case .malicious: "OpenSSF"
        case .ossFuzz: "OSS-Fuzz"
        case .android: "Android"
        case .bitnami: "Bitnami"
        case .chainguard: "Chainguard"
        case .curl: "curl"
        case .debian: "Debian"
        case .drupal: "Drupal"
        case .erlang: "EEF"
        case .haskell: "Haskell"
        case .julia: "Julia"
        case .ocaml: "OCaml"
        case .kubernetes: "Kubernetes"
        case .rConsortium: "R Consortium"
        case .homebrew: "Homebrew"
        case .redHat: "Red Hat"
        case .suse: "SUSE"
        case .ubuntu: "Ubuntu"
        case .almaLinux: "AlmaLinux"
        case .rockyLinux: "Rocky Linux"
        case .alpine: "Alpine"
        case .gsd: "GSD"
        case .other: "OSV.dev"
        }
    }

    /// De naam van de database zelf (een eigennaam, niet vertaald), voor de tooltip.
    public var name: String {
        switch self {
        case .gitHub: "GitHub Advisory Database"
        case .rustSec: "RustSec Advisory Database"
        case .pyPA: "PyPI Advisory Database (PyPA)"
        case .psf: "Python Software Foundation Vulnerability Database"
        case .go: "Go Vulnerability Database"
        case .rubySec: "RubySec Advisory Database"
        case .friendsOfPHP: "FriendsOfPHP Security Advisories"
        case .nvd: "National Vulnerability Database (NVD)"
        case .malicious: "OpenSSF Malicious Packages"
        case .ossFuzz: "OSS-Fuzz"
        case .android: "Android Security Bulletin"
        case .bitnami: "Bitnami Vulnerability Database"
        case .chainguard: "Chainguard Security Notices"
        case .curl: "curl CVEs"
        case .debian: "Debian Security Tracker"
        case .drupal: "Drupal Advisory Database"
        case .erlang: "Erlang Ecosystem Foundation CNA"
        case .haskell: "Haskell Security Advisory Database"
        case .julia: "Julia Security Advisory Database"
        case .ocaml: "OCaml Security Advisory Database"
        case .kubernetes: "Kubernetes Official CVE Feed"
        case .rConsortium: "R Consortium Advisory Database"
        case .homebrew: "Homebrew Advisory Database"
        case .redHat: "Red Hat Security Data"
        case .suse: "SUSE Security"
        case .ubuntu: "Ubuntu Security Notices"
        case .almaLinux: "AlmaLinux Security Advisory"
        case .rockyLinux: "Rocky Linux Security Advisory"
        case .alpine: "Alpine SecDB"
        case .gsd: "Global Security Database"
        case .other: "OSV.dev"
        }
    }

    /// De pagina van een id bij zijn eigen database; osv.dev als die database geen vaste
    /// pagina per id heeft (PyPA, OpenSSF en de meeste distributies).
    public static func pageURL(id: String) -> URL {
        let osv = URL(string: "https://osv.dev/vulnerability")!.appending(path: id)
        let prefix = id.split(separator: "-").first.map { $0.uppercased() } ?? ""
        switch prefix {
        case "GHSA": return URL(string: "https://github.com/advisories")!.appending(path: id)
        case "RUSTSEC": return URL(string: "https://rustsec.org/advisories")!.appending(path: "\(id).html")
        case "GO": return URL(string: "https://pkg.go.dev/vuln")!.appending(path: id)
        case "CVE": return URL(string: "https://nvd.nist.gov/vuln/detail")!.appending(path: id)
        case "USN": return URL(string: "https://ubuntu.com/security/notices")!.appending(path: id)
        case "RHSA", "RHBA", "RHEA": return URL(string: "https://access.redhat.com/errata")!.appending(path: id)
        default: return osv
        }
    }
}

/// Een link uit `references` van een OSV-record.
public struct VulnerabilityReference: Codable, Hashable, Sendable {
    /// "FIX", "ADVISORY", "REPORT", "ARTICLE", "WEB", "PACKAGE" …, in hoofdletters.
    public let type: String
    public let url: URL

    public init(type: String, url: URL) {
        self.type = type
        self.url = url
    }

    /// Eerst wat de oplossing laat zien, dan het advies zelf, dan de rest.
    var rank: Int {
        switch type {
        case "FIX": 0
        case "ADVISORY": 1
        case "REPORT": 2
        case "ARTICLE": 3
        case "WEB": 4
        case "PACKAGE": 5
        default: 6
        }
    }

    /// Zoveel links bewaart een kwetsbaarheid; een CVE van een veelgebruikte bibliotheek heeft er honderden.
    static let limit = 30

    /// FIX eerst, verder in de volgorde van het record; elke URL één keer, hooguit `limit`.
    static func ordered(_ references: [VulnerabilityReference]) -> [VulnerabilityReference] {
        var seen: Set<URL> = []
        let unique = references.filter { seen.insert($0.url).inserted }
        let sorted = unique.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }.map(\.element)
        return Array(sorted.prefix(limit))
    }
}

/// Een CVSS-vector uit `severity[]` van een OSV-record, met de score die Pullwatch eruit rekent.
public struct CVSSRating: Codable, Hashable, Sendable {
    /// Bv. "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H".
    public let vector: String
    /// 0.0 t/m 10.0, uitgerekend met `CVSSCalculator`.
    public let score: Double
    /// `severity[].source`: "NVD", "CNA" of "SELF"; nil is de database van het record zelf.
    let assessor: String?

    public init(vector: String, score: Double, assessor: String? = nil) {
        self.vector = vector
        self.score = score
        self.assessor = assessor
    }

    /// "3.1" of "4.0".
    public var version: String? { CVSSCalculator.version(of: vector) }

    /// "CRITICAL", "HIGH", "MODERATE" of "LOW"; nil bij 0.0.
    public var level: String? { CVSSCalculator.rating(score) }
}
