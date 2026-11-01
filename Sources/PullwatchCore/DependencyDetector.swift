import Foundation

/// Een package met exacte versie uit een lockfile of manifest, in OSV-termen.
public struct Dependency: Codable, Hashable, Sendable {
    /// OSV-ecosysteem: "Go", "npm", "NuGet", "PyPI", "Packagist", "crates.io" of "SwiftURL".
    public let ecosystem: String
    public let name: String
    public let version: String
    public let source: String
    /// Rechtstreeks door het project gevraagd (true), alleen via een ander package (false) of
    /// niet uit dit bestand af te leiden (nil; dan beslist het manifest, zie `DependencyDetector.direct`).
    public let isDirect: Bool?

    public init(ecosystem: String, name: String, version: String, source: String, isDirect: Bool? = nil) {
        self.ecosystem = ecosystem
        self.name = name
        self.version = version
        self.source = source
        self.isDirect = isDirect
    }

    /// Zelfde package en versie, ongeacht het bestand; sleutel voor de OSV-query.
    var withoutSource: Dependency {
        Dependency(ecosystem: ecosystem, name: name, version: version, source: "")
    }
}

/// Een direct gebruikt package in een repo: oudste versie als het in meerdere bestanden staat.
public struct PackageUse: Codable, Hashable, Sendable {
    public let ecosystem: String
    public let name: String
    public let version: String
    public let sources: [String]

    public init(ecosystem: String, name: String, version: String, sources: [String]) {
        self.ecosystem = ecosystem
        self.name = name
        self.version = version
        self.sources = sources
    }

    /// Sleutel voor de nieuwste versie in `VersionReport.latestPackages`.
    public var key: String { "\(ecosystem):\(name)" }
}

/// Leest packages met exacte versies voor de CVE-check. Versiebereiken (^1.2, >=3) tellen niet:
/// OSV heeft een exacte versie nodig. yarn.lock en pnpm-lock.yaml worden niet gelezen.
public enum DependencyDetector {
    public static func isRelevant(_ path: String) -> Bool {
        guard let name = path.split(separator: "/").last.map(String.init) else { return false }
        return name == "go.mod" || name == "package-lock.json" || name == "Package.resolved" || name == "composer.lock" || name == "Cargo.lock" || name == "poetry.lock" || name == "uv.lock"
            || name == "Directory.Packages.props" || name == "Directory.Build.props"
            || name.hasSuffix(".csproj") || name.hasSuffix(".fsproj")
            || (name.hasPrefix("requirements") && name.hasSuffix(".txt"))
    }

    public static func detect(path: String, content: String) -> [Dependency] {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        if name == "go.mod" { return goModules(content, path: path) }
        if name == "package-lock.json" { return npmLock(content, path: path) }
        if name == "composer.lock" { return composerLock(content, path: path) }
        if name == "Package.resolved" { return swiftPackages(content, path: path) }
        if name == "poetry.lock" || name == "uv.lock" { return tomlLock(content, path: path, ecosystem: "PyPI") }
        if name == "Cargo.lock" { return tomlLock(content, path: path, ecosystem: "crates.io", registryOnly: true) }
        if name.hasPrefix("requirements") { return requirements(content, path: path) }
        return nugetPackages(content, path: path)
    }

    /// `require x v1.2.3` en regels binnen `require ( … )`; de "v" valt weg zoals OSV verwacht.
    private static func goModules(_ content: String, path: String) -> [Dependency] {
        var result: [Dependency] = []
        var inBlock = false
        for raw in content.split(whereSeparator: \.isNewline) {
            let indirect = raw.contains("// indirect")
            var line = raw.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            line = line.trimmingCharacters(in: .whitespaces)
            if line == "require (" { inBlock = true; continue }
            if inBlock && line == ")" { inBlock = false; continue }
            if line.hasPrefix("require ") { line = String(line.dropFirst("require ".count)) } else if !inBlock { continue }
            let parts = line.split(separator: " ")
            guard parts.count == 2, parts[1].hasPrefix("v") else { continue }
            result.append(Dependency(ecosystem: "Go", name: String(parts[0]), version: String(parts[1].dropFirst()), source: path, isDirect: !indirect))
        }
        return result
    }

    /// lockfileVersion 2/3 (`packages`) en 1 (`dependencies`, alleen het hoogste niveau). Direct is
    /// alleen te zien in 2/3: een package op het hoogste niveau dat de root (`""`) zelf vraagt.
    private static func npmLock(_ content: String, path: String) -> [Dependency] {
        struct Entry: Decodable {
            let version: String?
            let dependencies: [String: String]?
            let devDependencies: [String: String]?
            let optionalDependencies: [String: String]?
        }
        struct V1Entry: Decodable { let version: String? }
        struct Lock: Decodable {
            let packages: [String: Entry]?
            let dependencies: [String: V1Entry]?
        }
        guard let lock = try? JSONDecoder().decode(Lock.self, from: Data(content.utf8)) else { return [] }
        var seen: Set<String> = []
        var result: [Dependency] = []
        func add(_ name: String, _ version: String?, isDirect: Bool? = nil) {
            guard !name.isEmpty, let version, StackDetector.version(from: version) != nil, !version.contains(":"),
                  seen.insert("\(name)@\(version)").inserted else { return }
            result.append(Dependency(ecosystem: "npm", name: name, version: version, source: path, isDirect: isDirect))
        }
        if let packages = lock.packages {
            let root = packages[""]
            let rootNames = root.map { root in
                Set([root.dependencies, root.devDependencies, root.optionalDependencies].compactMap { $0?.keys }.joined())
            }
            // Directe packages eerst, zodat die bij dezelfde naam@versie winnen.
            for (key, entry) in packages.sorted(by: { $0.key.count < $1.key.count }) {
                guard let range = key.range(of: "node_modules/", options: .backwards) else { continue }
                let name = String(key[range.upperBound...])
                add(name, entry.version, isDirect: rootNames.map { key == "node_modules/\(name)" && $0.contains(name) })
            }
        } else {
            for (name, entry) in lock.dependencies ?? [:] { add(name, entry.version) }
        }
        return result.sorted { ($0.name, $0.version) < ($1.name, $1.version) }
    }

    /// `packages` en `packages-dev`; de "v" van tags valt weg, branches (`dev-main`) tellen niet.
    private static func composerLock(_ content: String, path: String) -> [Dependency] {
        struct Package: Decodable { let name: String; let version: String }
        struct Lock: Decodable {
            let packages: [Package]?
            let packagesDev: [Package]?
            enum CodingKeys: String, CodingKey { case packages, packagesDev = "packages-dev" }
        }
        guard let lock = try? JSONDecoder().decode(Lock.self, from: Data(content.utf8)) else { return [] }
        return ((lock.packages ?? []) + (lock.packagesDev ?? [])).compactMap { package in
            guard !package.version.hasPrefix("dev-") else { return nil }
            let version = package.version.hasPrefix("v") ? String(package.version.dropFirst()) : package.version
            guard StackDetector.version(from: version) != nil else { return nil }
            return Dependency(ecosystem: "Packagist", name: package.name, version: version, source: path)
        }
    }

    /// Package.resolved v1 (`object.pins`, `repositoryURL`) en v2/v3 (`pins`, `location`). OSV kent
    /// Swift-packages als URL zonder schema en ".git": `github.com/apple/swift-nio`. Pins op een
    /// branch of commit (geen `version`) tellen niet.
    private static func swiftPackages(_ content: String, path: String) -> [Dependency] {
        struct Pin: Decodable {
            struct State: Decodable { let version: String? }
            let location: String?
            let repositoryURL: String?
            let state: State
        }
        struct Resolved: Decodable {
            struct Object: Decodable { let pins: [Pin] }
            let pins: [Pin]?
            let object: Object?
        }
        guard let resolved = try? JSONDecoder().decode(Resolved.self, from: Data(content.utf8)) else { return [] }
        return (resolved.pins ?? resolved.object?.pins ?? []).compactMap { pin in
            guard let url = pin.location ?? pin.repositoryURL, let version = pin.state.version else { return nil }
            return Dependency(ecosystem: "SwiftURL", name: swiftPackageName(url), version: version, source: path)
        }
    }

    /// "https://github.com/apple/swift-nio.git" en "git@github.com:apple/swift-nio.git" → "github.com/apple/swift-nio".
    static func swiftPackageName(_ url: String) -> String {
        var name = url
        if let scheme = name.range(of: "://") { name = String(name[scheme.upperBound...]) }
        if name.hasPrefix("git@") { name = String(name.dropFirst(4)).replacingOccurrences(of: ":", with: "/") }
        if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
        if name.hasSuffix("/") { name = String(name.dropLast()) }
        return name
    }

    /// `[[package]]`-blokken met `name = "…"` en `version = "…"` (poetry.lock, uv.lock, Cargo.lock).
    /// `registryOnly`: alleen packages met `source = "registry+…"`; workspace-crates en git-forks
    /// staan niet op crates.io.
    private static func tomlLock(_ content: String, path: String, ecosystem: String, registryOnly: Bool = false) -> [Dependency] {
        var result: [Dependency] = []
        var name: String?
        var version: String?
        var fromRegistry = false
        func flush() {
            if let name, let version, !registryOnly || fromRegistry {
                result.append(Dependency(ecosystem: ecosystem, name: name, version: version, source: path))
            }
            name = nil
            version = nil
            fromRegistry = false
        }
        for raw in content.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                flush()
                continue
            }
            if line.hasPrefix("source = \"registry+") { fromRegistry = true }
            if let m = line.wholeMatch(of: /(name|version)\s*=\s*"([^"]+)"/) {
                if m.output.1 == "name" { name = name ?? String(m.output.2) } else { version = version ?? String(m.output.2) }
            }
        }
        flush()
        return result
    }

    /// Alleen `pakket==versie`; extras (`pakket[x]==1`) en markers (`; python_version…`) worden genegeerd.
    private static func requirements(_ content: String, path: String) -> [Dependency] {
        content.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let spec = line.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            guard let m = spec.trimmingCharacters(in: .whitespaces).wholeMatch(of: /([A-Za-z0-9._-]+)(\[[^\]]*\])?\s*==\s*([^\s,]+)/) else {
                return nil
            }
            return Dependency(ecosystem: "PyPI", name: String(m.output.1), version: String(m.output.3), source: path, isDirect: true)
        }
    }

    /// `<PackageReference Include="X" Version="1.2.3" />` en `<PackageVersion …>`; attributen in elke volgorde.
    private static func nugetPackages(_ content: String, path: String) -> [Dependency] {
        content.matches(of: /<Package(?:Reference|Version)\b([^>]*)>/).compactMap { match in
            let attributes = String(match.output.1)
            guard let include = attributes.firstMatch(of: /Include="([^"]+)"/)?.output.1,
                  let version = attributes.firstMatch(of: /Version="([^"$\[\]()*]+)"/)?.output.1 else { return nil }
            return Dependency(ecosystem: "NuGet", name: String(include), version: String(version), source: path, isDirect: true)
        }
    }

    /// Namen die een manifest rechtstreeks vraagt, voor lockfiles die dat zelf niet zeggen
    /// (composer.lock, Cargo.lock, poetry.lock, uv.lock, package-lock v1).
    public static func directNames(path: String, content: String) -> (ecosystem: String, names: Set<String>)? {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        switch name {
        case "package.json":
            struct Manifest: Decodable {
                let dependencies: [String: String]?
                let devDependencies: [String: String]?
                let optionalDependencies: [String: String]?
            }
            guard let manifest = try? JSONDecoder().decode(Manifest.self, from: Data(content.utf8)) else { return nil }
            let names = [manifest.dependencies, manifest.devDependencies, manifest.optionalDependencies].compactMap { $0?.keys }.joined()
            return ("npm", Set(names))
        case "composer.json":
            struct Manifest: Decodable {
                let require: [String: String]?
                let requireDev: [String: String]?
                enum CodingKeys: String, CodingKey { case require, requireDev = "require-dev" }
            }
            guard let manifest = try? JSONDecoder().decode(Manifest.self, from: Data(content.utf8)) else { return nil }
            let names = [manifest.require, manifest.requireDev].compactMap { $0?.keys }.joined()
                .filter { $0 != "php" && !$0.hasPrefix("ext-") && $0.contains("/") }
            return ("Packagist", Set(names.map { $0.lowercased() }))
        case "pyproject.toml":
            return ("PyPI", pyprojectNames(content))
        case "Cargo.toml":
            return ("crates.io", Set(tomlKeys(content, sections: ["dependencies", "dev-dependencies", "build-dependencies"])))
        default:
            return nil
        }
    }

    /// PyPI-namen vergelijken zoals PEP 503: kleine letters, `_` en `.` worden `-`.
    static func normalizedPyPIName(_ name: String) -> String {
        name.lowercased().replacing(/[-_.]+/, with: "-")
    }

    /// `[project] dependencies = [ "pakket>=1", … ]` en de sleutels van `[tool.poetry.dependencies]` (zonder python).
    private static func pyprojectNames(_ content: String) -> Set<String> {
        var names: Set<String> = []
        var section = ""
        var inArray = false
        for raw in content.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && !inArray {
                section = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                continue
            }
            if section == "project" && line.hasPrefix("dependencies") && line.contains("[") {
                inArray = true
            }
            if inArray {
                for match in line.matches(of: /"([A-Za-z0-9][A-Za-z0-9._-]*)/) {
                    names.insert(normalizedPyPIName(String(match.output.1)))
                }
                // Extras (`requests[socks]`) staan binnen de quotes; alleen een "]" daarbuiten sluit de lijst.
                if line.replacing(/"[^"]*"/, with: "").contains("]") { inArray = false }
                continue
            }
            if section == "tool.poetry.dependencies" || section.hasPrefix("tool.poetry.group.") && section.hasSuffix(".dependencies"),
               let m = line.firstMatch(of: /^([A-Za-z0-9][A-Za-z0-9._-]*)\s*=/) {
                let name = String(m.output.1)
                if name != "python" { names.insert(normalizedPyPIName(name)) }
            }
        }
        return names
    }

    /// Sleutels (`naam = …`) in de opgegeven TOML-secties.
    private static func tomlKeys(_ content: String, sections: Set<String>) -> [String] {
        var keys: [String] = []
        var inSection = false
        for raw in content.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inSection = sections.contains(line.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")))
                continue
            }
            if inSection, let m = line.firstMatch(of: /^([A-Za-z0-9_-]+)\s*=/) {
                keys.append(String(m.output.1))
            }
        }
        return keys
    }

    /// Directe packages van een repo, één per (ecosysteem, naam) met de oudste versie en alle bronnen.
    /// Een package zonder eigen markering telt als het manifest het noemt; Swift-pins altijd (geen manifest).
    public static func direct(_ dependencies: [Dependency], manifests: [String: Set<String>]) -> [PackageUse] {
        func isDirect(_ dependency: Dependency) -> Bool {
            if let marked = dependency.isDirect { return marked }
            if dependency.ecosystem == "SwiftURL" { return true }
            guard let names = manifests[dependency.ecosystem] else { return false }
            if dependency.ecosystem == "PyPI" { return names.contains(normalizedPyPIName(dependency.name)) }
            return names.contains(dependency.name)
        }
        var order: [String] = []
        var uses: [String: PackageUse] = [:]
        for dependency in dependencies where isDirect(dependency) {
            let key = "\(dependency.ecosystem):\(dependency.name)"
            guard let current = uses[key] else {
                order.append(key)
                uses[key] = PackageUse(ecosystem: dependency.ecosystem, name: dependency.name, version: dependency.version, sources: [dependency.source])
                continue
            }
            uses[key] = PackageUse(
                ecosystem: current.ecosystem,
                name: current.name,
                version: VersionChecker.isOlder(dependency.version, than: current.version) ? dependency.version : current.version,
                sources: current.sources.contains(dependency.source) ? current.sources : current.sources + [dependency.source]
            )
        }
        return order.compactMap { uses[$0] }
    }
}
