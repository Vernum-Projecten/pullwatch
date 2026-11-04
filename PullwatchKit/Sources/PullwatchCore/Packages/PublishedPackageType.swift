import Foundation

/// Het soort package in het register van een dienst: npm, container, NuGet, Maven, RubyGems en de
/// soorten die GitLab en Azure Artifacts erbij hebben. Een open lijst: een soort die Pullwatch nog
/// niet kent, blijft bij het lezen gewoon zijn naam houden, zodat opgeslagen gegevens van een
/// nieuwere versie nooit stukgaan.
public struct PublishedPackageType: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.lowercased()
    }

    public static let npm = Self(rawValue: "npm")
    public static let maven = Self(rawValue: "maven")
    public static let rubyGems = Self(rawValue: "rubygems")
    /// Het oude Docker-register van GitHub (docker.pkg.github.com), voor ghcr.io.
    public static let docker = Self(rawValue: "docker")
    public static let nuGet = Self(rawValue: "nuget")
    /// Een container-image, op GitHub in ghcr.io.
    public static let container = Self(rawValue: "container")
    public static let pyPI = Self(rawValue: "pypi")
    public static let helm = Self(rawValue: "helm")
    public static let generic = Self(rawValue: "generic")

    /// Het ecosysteem zoals de versiecheck het noemt (`PackageUse.ecosystem`, de namen van OSV),
    /// voor het herkennen van een eigen package tussen de dependencies; nil voor een soort die
    /// de check niet als dependency leest.
    public var dependencyEcosystem: String? {
        switch self {
        case .npm: "npm"
        case .maven: "Maven"
        case .rubyGems: "RubyGems"
        case .nuGet: "NuGet"
        case .pyPI: "PyPI"
        default: nil
        }
    }
}
