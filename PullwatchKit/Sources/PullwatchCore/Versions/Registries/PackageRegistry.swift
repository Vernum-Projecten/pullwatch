import Foundation

/// Nieuwste stabiele versie van een package, rechtstreeks uit het register van het ecosysteem.
enum PackageRegistry {
    /// crates.io weigert verzoeken zonder User-Agent; de andere registers krijgen hem ook.
    static let userAgent = "Pullwatch (https://github.com/alessandro823/pullwatch)"

    /// nil voor een ecosysteem zonder centraal register (SwiftURL) of een onbekend ecosysteem.
    public static func url(ecosystem: String, name: String) -> URL? {
        let string: String
        switch ecosystem {
        case "Go":
            string = "https://proxy.golang.org/\(goEscaped(name))/@latest"
        case "npm":
            string = "https://registry.npmjs.org/\(name.replacingOccurrences(of: "/", with: "%2F"))/latest"
        case "Packagist":
            string = "https://repo.packagist.org/p2/\(name.lowercased()).json"
        case "NuGet":
            string = "https://api.nuget.org/v3-flatcontainer/\(name.lowercased())/index.json"
        case "PyPI":
            string = "https://pypi.org/pypi/\(name)/json"
        case "crates.io":
            string = "https://crates.io/api/v1/crates/\(name)"
        case "RubyGems":
            string = "https://rubygems.org/api/v1/versions/\(name)/latest.json"
        default:
            return nil
        }
        return URL(string: string)
    }

    /// De Go-proxy wil hoofdletters als "!" plus kleine letter: "BurntSushi" → "!burnt!sushi".
    static func goEscaped(_ path: String) -> String {
        path.map { $0.isUppercase ? "!\($0.lowercased())" : String($0) }.joined()
    }

    /// nil als het register geen stabiele versie geeft (alleen pre-releases of een Go-pseudo-versie).
    static func decodeLatest(ecosystem: String, name: String, data: Data) throws -> String? {
        switch ecosystem {
        case "Go":
            struct Info: Decodable { let Version: String }
            let version = try JSONDecoding.decode(Info.self, from: data).Version
            // Zonder tags geeft de proxy een pseudo-versie (v0.0.0-20240101120000-abcdef123456).
            guard version.firstMatch(of: /\d{14}-[0-9a-f]{12}$/) == nil else { return nil }
            return version.droppingVersionPrefix
        case "npm":
            struct Info: Decodable { let version: String }
            return try JSONDecoding.decode(Info.self, from: data).version
        case "Packagist":
            struct Response: Decodable {
                struct Package: Decodable { let version: String }
                let packages: [String: [Package]]
            }
            let packages = try JSONDecoding.decode(Response.self, from: data).packages[name.lowercased()] ?? []
            return highestStable(packages.map(\.version.droppingVersionPrefix))
        case "NuGet":
            struct Index: Decodable { let versions: [String] }
            return highestStable(try JSONDecoding.decode(Index.self, from: data).versions)
        case "PyPI":
            struct Response: Decodable {
                struct Info: Decodable { let version: String }
                let info: Info
            }
            return try JSONDecoding.decode(Response.self, from: data).info.version
        case "crates.io":
            struct Response: Decodable {
                struct Crate: Decodable { let max_stable_version: String? }
                let crate: Crate
            }
            return try JSONDecoding.decode(Response.self, from: data).crate.max_stable_version
        case "RubyGems":
            // `{"version":"7.2.1"}`; "unknown" voor een onbekende gem. Een pre-release heeft letters
            // in de versie ("8.0.0.beta1").
            struct Info: Decodable { let version: String }
            let version = try JSONDecoding.decode(Info.self, from: data).version
            return version.contains(where: \.isLetter) ? nil : version
        default:
            return nil
        }
    }

    /// Hoogste versie zonder pre-release-deel ("-RC1", "-beta") en zonder branches ("dev-main").
    static func highestStable(_ versions: [String]) -> String? {
        versions
            .filter { !$0.contains("-") && !$0.hasPrefix("dev") && StackDetector.version(from: $0) != nil }
            .max { VersionChecker.isOlder($0, than: $1) }
    }

    /// nil bij elke fout (404 voor een private module, netwerk, onleesbaar antwoord): zo'n package
    /// is dan niet te checken, maar de rest van de check gaat door.
    public static func latest(ecosystem: String, name: String, http: any HTTPClient, now: Date = Date()) async -> String? {
        guard let url = url(ecosystem: ecosystem, name: name) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await http.send(request)
            try HTTPStatus.check(response, now: now)
            return try decodeLatest(ecosystem: ecosystem, name: name, data: data)
        } catch {
            return nil
        }
    }
}
