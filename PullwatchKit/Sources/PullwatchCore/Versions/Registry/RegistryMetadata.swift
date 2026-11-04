import Foundation

/// Metadata per versie uit de registers, met één verzoek per package waar het register dat
/// toelaat. Het document geeft ook de nieuwste versie, dus het vervangt het verzoek van
/// `PackageRegistry.latest`:
///
/// - npm: het verkorte packument (`application/vnd.npm.install-v1+json`) met per versie
///   `dependencies`, `peerDependencies`, `peerDependenciesMeta`, `engines` en `deprecated`.
/// - Packagist: `p2/<naam>.json` (Composer 2, verkleind: elke versie erft wat de vorige had), met
///   per versie `require`, `php` daarin.
/// - crates.io: `/api/v1/crates/<naam>` met per versie `rust_version` en `yanked`; de dependencies
///   per versie alleen als ze nodig zijn (`/api/v1/crates/<naam>/<versie>/dependencies`).
/// - NuGet: de registration index met per versie de dependency groups (target frameworks); bij
///   een groot package de pagina's die versies vanaf de oudste install bevatten.
/// - RubyGems: `/api/v1/versions/<naam>.json` met `ruby_version` en `rubygems_version`; de
///   dependencies alleen als ze nodig zijn (`/api/v2/rubygems/<naam>/versions/<versie>.json`).
/// - PyPI: `/pypi/<naam>/json` met `requires_python` per release; `requires_dist` per release
///   alleen als het nodig is (`/pypi/<naam>/<versie>/json`).
/// - Go: `@latest`, en per versie de go.mod (`@v/<versie>.mod`) voor de `go`-regel en de
///   `require`s; de lijst van versies (`@v/list`) alleen als de nieuwste niet bruikbaar is.
enum RegistryMetadata {
    /// Het document met alle versies; nil zonder centraal register.
    static func documentURL(ecosystem: String, name: String) -> URL? {
        switch ecosystem {
        case "npm":
            return URL(string: "https://registry.npmjs.org/\(name.replacingOccurrences(of: "/", with: "%2F"))")
        case "NuGet":
            return URL(string: "https://api.nuget.org/v3/registration5-gz-semver2/\(name.lowercased())/index.json")
        case "RubyGems":
            return URL(string: "https://rubygems.org/api/v1/versions/\(name).json")
        default:
            // Go, Packagist, PyPI en crates.io: hetzelfde document als voor de nieuwste versie.
            return PackageRegistry.url(ecosystem: ecosystem, name: name)
        }
    }

    /// Het document van één versie, voor wat het hoofddocument niet geeft; nil als het hoofddocument alles heeft.
    static func detailURL(ecosystem: String, name: String, version: String) -> URL? {
        switch ecosystem {
        case "crates.io": URL(string: "https://crates.io/api/v1/crates/\(name)/\(version)/dependencies")
        case "RubyGems": URL(string: "https://rubygems.org/api/v2/rubygems/\(name)/versions/\(version).json")
        case "PyPI": URL(string: "https://pypi.org/pypi/\(name)/\(version)/json")
        case "Go": URL(string: "https://proxy.golang.org/\(PackageRegistry.goEscaped(name))/@v/v\(version).mod")
        default: nil
        }
    }

    static func listURL(goModule name: String) -> URL? {
        URL(string: "https://proxy.golang.org/\(PackageRegistry.goEscaped(name))/@v/list")
    }

    // MARK: - Ophalen

    /// Haalt het document van een package op en houdt alleen stabiele versies vanaf `floor` (de
    /// oudste install) plus de installs zelf (`keep`). Wat `cached` per versie al had, blijft. Voor Go
    /// ook de go.mod van de nieuwste versie. nil bij elke fout, zoals `PackageRegistry.latest`.
    public static func fetch(
        ecosystem: String, name: String, floor: String?, keep: Set<String> = [], cached: PackageMetadata? = nil,
        http: any HTTPClient, now: Date = Date()
    ) async -> PackageMetadata? {
        guard let url = documentURL(ecosystem: ecosystem, name: name) else { return nil }
        do {
            let data = try await get(url, ecosystem: ecosystem, http: http, now: now)
            var decoded = try decode(ecosystem: ecosystem, name: name, data: data)
            if ecosystem == "NuGet" {
                decoded.versions.merge(try await nugetPages(data: data, floor: floor, http: http, now: now)) { first, _ in first }
                decoded.latest = PackageRegistry.highestStable(decoded.versions.filter { !$0.value.isWithdrawn }.map(\.key))
            }
            var metadata = PackageMetadata(latest: decoded.latest, versions: decoded.versions, isComplete: ecosystem != "Go")
                .pruned(floor: floor, keep: keep)
                .filling(from: cached)
            if ecosystem == "Go", let latest = metadata.latest, metadata.versions[latest]?.dependencies == nil,
               let detail = await detail(ecosystem: ecosystem, name: name, version: latest, http: http, now: now) {
                metadata.versions[latest] = detail
            }
            return metadata
        } catch {
            return nil
        }
    }

    /// De gegevens van één versie uit zijn eigen document (`detailURL`); nil bij een fout.
    public static func detail(ecosystem: String, name: String, version: String, http: any HTTPClient, now: Date = Date()) async -> VersionMetadata? {
        guard let url = detailURL(ecosystem: ecosystem, name: name, version: version) else { return nil }
        do {
            return try decodeDetail(ecosystem: ecosystem, data: try await get(url, ecosystem: ecosystem, http: http, now: now))
        } catch {
            return nil
        }
    }

    /// Alle versies van een Go-module (`@v/list`), zonder "v"; nil bij een fout.
    static func goVersions(module name: String, http: any HTTPClient, now: Date = Date()) async -> [String]? {
        guard let url = listURL(goModule: name), let data = try? await get(url, ecosystem: "Go", http: http, now: now) else { return nil }
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map {
            $0.droppingVersionPrefix
        }
    }

    static func get(_ url: URL, ecosystem: String, http: any HTTPClient, now: Date) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(
            ecosystem == "npm" ? "application/vnd.npm.install-v1+json; q=1.0, application/json; q=0.8" : "application/json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(PackageRegistry.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await http.send(request)
        try HTTPStatus.check(response, now: now)
        return data
    }
}

extension PackageMetadata {
    /// Alleen stabiele versies vanaf `floor` en de versies in `keep`; zonder `floor` alles.
    func pruned(floor: String?, keep: Set<String>) -> PackageMetadata {
        guard let lowest = floor.flatMap({ Version($0) }) else { return self }
        let kept = Set(keep.compactMap { Version($0) })
        let versions = versions.filter { text, _ in
            guard let version = Version(text) else { return false }
            if kept.contains(version) || text == latest { return true }
            return !version.isPrerelease && version >= lowest
        }
        return PackageMetadata(latest: latest, versions: versions, isComplete: isComplete)
    }
}
