import Foundation

/// Een externe bron waar Pullwatch gegevens vandaan haalt en die je kunt uitzetten.
/// De ruwe waarde staat in `AppConfig.disabledSources`, dus hernoem een case niet.
public enum DataSourceID: String, Codable, CaseIterable, Sendable {
    case osv, gitHubAdvisoryDatabase, gitHubSecurity, azureDevOpsAdvancedSecurity
    case npm, pyPI, cratesIO, nuGet, rubyGems, packagist, goProxy, endOfLife, swiftOrg
    case ciChecks
}

public enum DataSourceGroup: Sendable {
    case vulnerabilities, versions
    /// Wat Pullwatch naast de PR's zelf over een pull request ophaalt (de checks).
    case pullRequests
}

extension LocalizedStringResource.BundleDescription {
    /// De teksten van PullwatchCore in de taal die de app gekozen heeft.
    fileprivate static var localizedCore: Self { .atURL(Bundle.localizedCore.bundleURL) }
}

public struct DataSource: Sendable, Identifiable {
    public let id: DataSourceID
    public let group: DataSourceGroup
    /// De naam zoals die in de app staat, in de taal van de app. Een eigennaam (OSV.dev, npm)
    /// blijft zoals hij is; een omschrijving (GitHub-beveiliging) wordt vertaald.
    public var name: String { localizedName.map { String(localized: $0) } ?? properName }
    /// De eigennaam, of de Nederlandse naam als er een vertaling is (`localizedName`).
    private let properName: String
    private let localizedName: LocalizedStringResource?
    /// Wat de bron levert, in gewone taal.
    public let summary: LocalizedStringResource
    /// De adressen die Pullwatch aanroept. Bij GitHub-beveiliging en Azure DevOps Advanced
    /// Security is dat de publieke standaard; een Enterprise- of eigen server gebruikt de
    /// server van het account zelf.
    public let endpoints: [URL]
    /// De website van de bron, om meer over hem te lezen.
    public let site: URL

    /// Alle bronnen, in de volgorde van de tabellen in het ontwerp.
    public static let all: [DataSource] = [
        DataSource(
            id: .osv, group: .vulnerabilities, name: "OSV.dev",
            summary: LocalizedStringResource("Bekende kwetsbaarheden (CVE's en GHSA's) in de packages die je repo's gebruiken", bundle: .localizedCore),
            endpoints: ["https://api.osv.dev"], site: "https://osv.dev"),
        DataSource(
            id: .gitHubAdvisoryDatabase, group: .vulnerabilities, name: "GitHub Advisory Database",
            summary: LocalizedStringResource("Aanvullende details bij een gevonden kwetsbaarheid: ernst, CVSS, CWE en publicatie", bundle: .localizedCore),
            endpoints: ["https://api.github.com"], site: "https://github.com/advisories"),
        DataSource(
            id: .gitHubSecurity, group: .vulnerabilities, name: "GitHub-beveiliging", localizedName: LocalizedStringResource("GitHub-beveiliging", bundle: .localizedCore),
            summary: LocalizedStringResource("Code scanning, secret scanning en de eigen adviezen van een repo", bundle: .localizedCore),
            endpoints: ["https://api.github.com"], site: "https://github.com/features/security"),
        DataSource(
            id: .azureDevOpsAdvancedSecurity, group: .vulnerabilities, name: "Azure DevOps Advanced Security",
            summary: LocalizedStringResource("Beveiligingsmeldingen van Advanced Security per repo, ook over kwetsbare packages", bundle: .localizedCore),
            endpoints: ["https://advsec.dev.azure.com"], site: "https://azure.microsoft.com/products/devops/github-advanced-security"),
        DataSource(
            id: .npm, group: .versions, name: "npm",
            summary: LocalizedStringResource("Nieuwste versie en gegevens van npm-packages (JavaScript)", bundle: .localizedCore),
            endpoints: ["https://registry.npmjs.org"], site: "https://www.npmjs.com"),
        DataSource(
            id: .pyPI, group: .versions, name: "PyPI",
            summary: LocalizedStringResource("Nieuwste versie en gegevens van Python-packages", bundle: .localizedCore),
            endpoints: ["https://pypi.org/pypi"], site: "https://pypi.org"),
        DataSource(
            id: .cratesIO, group: .versions, name: "crates.io",
            summary: LocalizedStringResource("Nieuwste versie en gegevens van Rust-packages", bundle: .localizedCore),
            endpoints: ["https://crates.io/api/v1/crates"], site: "https://crates.io"),
        DataSource(
            id: .nuGet, group: .versions, name: "NuGet",
            summary: LocalizedStringResource("Nieuwste versie en gegevens van .NET-packages", bundle: .localizedCore),
            endpoints: ["https://api.nuget.org"], site: "https://www.nuget.org"),
        DataSource(
            id: .rubyGems, group: .versions, name: "RubyGems",
            summary: LocalizedStringResource("Nieuwste versie en gegevens van Ruby-packages", bundle: .localizedCore),
            endpoints: ["https://rubygems.org/api"], site: "https://rubygems.org"),
        DataSource(
            id: .packagist, group: .versions, name: "Packagist",
            summary: LocalizedStringResource("Nieuwste versie en gegevens van PHP-packages", bundle: .localizedCore),
            endpoints: ["https://repo.packagist.org"], site: "https://packagist.org"),
        DataSource(
            id: .goProxy, group: .versions, name: "Go-moduleproxy", localizedName: LocalizedStringResource("Go-moduleproxy", bundle: .localizedCore),
            summary: LocalizedStringResource("Nieuwste versie en gegevens van Go-modules", bundle: .localizedCore),
            endpoints: ["https://proxy.golang.org"], site: "https://proxy.golang.org"),
        DataSource(
            id: .endOfLife, group: .versions, name: "endoflife.date",
            summary: LocalizedStringResource("Releasecycli en einddatum van ondersteuning van runtimes zoals Go, .NET en Node", bundle: .localizedCore),
            endpoints: ["https://endoflife.date/api/v1/products"], site: "https://endoflife.date"),
        DataSource(
            id: .swiftOrg, group: .versions, name: "swift.org",
            summary: LocalizedStringResource("Swift-releases; Swift heeft geen einddatum van ondersteuning", bundle: .localizedCore),
            endpoints: ["https://www.swift.org/api/v1/install/releases.json"], site: "https://www.swift.org"),
        DataSource(
            id: .ciChecks, group: .pullRequests, name: "CI-checks", localizedName: LocalizedStringResource("CI-checks", bundle: .localizedCore),
            summary: LocalizedStringResource("De checks (CI) van pull requests: hoeveel er geslaagd, mislukt of nog bezig zijn, en de melding als die van je eigen PR mislukken", bundle: .localizedCore),
            endpoints: ["https://api.github.com", "https://dev.azure.com", "https://gitlab.com/api/v4"],
            site: "https://docs.github.com/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/about-status-checks"),
    ]

    public static func source(_ id: DataSourceID) -> DataSource {
        guard let source = all.first(where: { $0.id == id }) else {
            preconditionFailure("Bron \(id.rawValue) staat niet in de catalogus")
        }
        return source
    }

    /// De naam in de taal van `bundle` (een `.lproj` van PullwatchCore), voor het gekopieerde
    /// overzicht in een andere taal dan die van de app.
    func name(bundle: Bundle) -> String {
        guard let localizedName else { return properName }
        return bundle.localizedString(forKey: localizedName.key, value: String(localized: localizedName), table: localizedName.table)
    }

    /// `localizedName` alleen voor een naam die geen eigennaam is; `name` is dan de Nederlandse.
    private init(id: DataSourceID, group: DataSourceGroup, name: String, localizedName: LocalizedStringResource? = nil,
                 summary: LocalizedStringResource, endpoints: [StaticString], site: StaticString) {
        self.id = id
        self.group = group
        self.properName = name
        self.localizedName = localizedName
        self.summary = summary
        self.endpoints = endpoints.map { URL(string: "\($0)")! }
        self.site = URL(string: "\(site)")!
    }
}

extension DataSourceID {
    /// De registry voor een ecosysteem, met de namen van `PackageRegistry`.
    public static func registry(ecosystem: String) -> DataSourceID? {
        switch ecosystem {
        case "npm": .npm
        case "PyPI": .pyPI
        case "crates.io": .cratesIO
        case "NuGet": .nuGet
        case "RubyGems": .rubyGems
        case "Packagist": .packagist
        case "Go": .goProxy
        default: nil
        }
    }

    /// Waar de releases van een product vandaan komen: Swift van swift.org, de rest van endoflife.date.
    public static func releases(product: String) -> DataSourceID {
        product == "swift" ? .swiftOrg : .endOfLife
    }
}
