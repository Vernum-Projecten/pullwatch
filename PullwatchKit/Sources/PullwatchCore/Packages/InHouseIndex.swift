import Foundation

/// De gepubliceerde packages van de accounts, op de sleutel waarmee de versiecheck een dependency
/// noemt ("ecosysteem:naam", genormaliseerd zoals het register vergelijkt). Een treffer is alleen
/// een kandidaat: een dependency is pas eigen met bewijs uit de lockfile (`InHouseEvidence`), want
/// een organisatie kan een fork van een publiek package onder dezelfde naam publiceren (#214).
///
/// Per ecosysteem:
/// - npm: de naam met scope, precies ("@acme/ui"). GitHub noemt een npm-package zonder scope
///   ("ui" onder eigenaar "acme"); daar is het altijd `@eigenaar/naam`, en "ui" alleen zou een
///   publiek package met die naam overnemen. GitLab noemt de scope altijd; Azure Artifacts laat
///   wat uit een upstream (npmjs.com) komt al weg, dus daar telt een naam zonder scope precies.
/// - NuGet: de id zonder verschil tussen hoofd- en kleine letters.
/// - Maven: `groupId:artifactId`; GitHub schrijft "com.acme.ui", GitLab "com/acme/ui", Azure
///   "com.acme:ui".
/// - RubyGems en Packagist: de naam, zonder verschil tussen hoofd- en kleine letters.
/// - PyPI: zoals PEP 503 (kleine letters, `-`, `_` en `.` gelijk); crates.io: `-` en `_` gelijk.
/// - Go: het modulepad, precies.
///
/// Container-images en Helm-charts horen bij geen ecosysteem van de dependency-check
/// (`PublishedPackageType.dependencyEcosystem`): een `FROM` in een Dockerfile leest de check alleen
/// als runtime (Node, PHP, .NET), niet als eigen image, dus een image valt hier buiten.
struct InHouseIndex {
    private let packages: [String: PublishedPackage]

    /// Bij twee packages met dezelfde sleutel (twee accounts) telt het eerste. `kinds` geeft per
    /// account de dienst; zonder telt een npm-naam zonder scope zoals bij GitHub.
    init(_ published: [PublishedPackage], kinds: [UUID: ProviderKind] = [:]) {
        var packages: [String: PublishedPackage] = [:]
        for package in published {
            for key in Self.keys(of: package, kind: kinds[package.accountId]) where packages[key] == nil {
                packages[key] = package
            }
        }
        self.packages = packages
    }

    var isEmpty: Bool { packages.isEmpty }

    /// Het eigen package voor een dependency; nil als geen gevolgde repo het publiceert.
    func match(ecosystem: String, name: String) -> PublishedPackage? {
        packages[Self.key(ecosystem: ecosystem, name: name)]
    }

    /// Als `match(ecosystem:name:)`, voor een `PackageUse.key`.
    func match(key: String) -> PublishedPackage? {
        VersionChecker.split(key).flatMap { match(ecosystem: $0.0, name: $0.1) }
    }

    // MARK: - Sleutels

    /// De sleutel van een dependency.
    static func key(ecosystem: String, name: String) -> String {
        "\(ecosystem):\(normalized(ecosystem: ecosystem, name: name))"
    }

    /// De sleutels waaronder een dependency dit package kan noemen; leeg voor een soort zonder
    /// ecosysteem in de check.
    static func keys(of package: PublishedPackage, kind: ProviderKind? = nil) -> [String] {
        guard let ecosystem = package.type.dependencyEcosystem else { return [] }
        let name = package.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return [] }
        switch ecosystem {
        case "npm":
            if name.hasPrefix("@") { return [key(ecosystem: ecosystem, name: name)] }
            if let kind, kind != .gitHub { return [key(ecosystem: ecosystem, name: name)] }
            let owner = package.owner.lowercased()
            return owner.isEmpty ? [] : [key(ecosystem: ecosystem, name: "@\(owner)/\(name)")]
        case "Maven":
            return mavenCoordinates(name).map { key(ecosystem: ecosystem, name: $0) }
        default:
            return [key(ecosystem: ecosystem, name: name)]
        }
    }

    static func normalized(ecosystem: String, name: String) -> String {
        switch ecosystem {
        case "PyPI": DependencyDetector.normalizedPyPIName(name)
        case "crates.io": name.lowercased().replacingOccurrences(of: "_", with: "-")
        case "NuGet", "RubyGems", "Maven", "Packagist": name.lowercased()
        default: name
        }
    }

    /// De vormen `groupId:artifactId` van een Maven-naam in een register: "com.acme:ui",
    /// "com.acme.ui" (GitHub) of "com/acme/ui" (GitLab). Bij een naam met punten is niet te zien
    /// waar de groep ophoudt, dus elke splitsing telt; een dependency heeft er maar één.
    static func mavenCoordinates(_ name: String) -> [String] {
        if name.contains(":") {
            let parts = name.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return [] }
            return ["\(parts[0].replacingOccurrences(of: "/", with: ".")):\(parts[1])"]
        }
        if name.contains("/") {
            // GitLab: het pad van de groep, dan het artifact.
            let parts = name.split(separator: "/")
            guard parts.count >= 2, let artifact = parts.last else { return [] }
            return ["\(parts.dropLast().joined(separator: ".")):\(artifact)"]
        }
        let parts = name.split(separator: ".")
        guard parts.count >= 2 else { return [] }
        return (1..<parts.count).map { split in
            "\(parts[..<split].joined(separator: ".")):\(parts[split...].joined(separator: "."))"
        }
    }
}
