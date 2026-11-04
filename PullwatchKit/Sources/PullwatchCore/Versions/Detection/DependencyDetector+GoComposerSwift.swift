import Foundation

extension DependencyDetector {
    // MARK: - Go

    /// `require x v1.2.3` en regels binnen `require ( … )`; de "v" valt weg zoals OSV verwacht.
    /// `// indirect` is transitief; go.mod zegt niet via welk package.
    static func goModules(_ content: String, path: String) -> [Dependency] {
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
            result.append(Dependency(ecosystem: "Go", name: String(parts[0]), version: String(parts[1].dropFirst()), source: path, isDirect: !indirect,
                                     requested: String(parts[1])))
        }
        return result
    }

    // MARK: - Composer

    /// `packages` is runtime, `packages-dev` dev; de "v" van tags valt weg, branches (`dev-main`)
    /// tellen niet. `require` van elk package is de graaf; direct volgt uit composer.json.
    static func composerLock(_ content: String, path: String) -> LockfileRead {
        struct Package: Decodable {
            struct Dist: Decodable { let url: String? }
            let name: String
            let version: String
            let require: [String: String]
            /// Waar Composer het archief haalt; bij een eigen register (GitLab) de URL daarvan.
            let dist: Dist?
            let notificationURL: String?
            enum CodingKeys: String, CodingKey { case name, version, require, dist, notificationURL = "notification-url" }
            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decode(String.self, forKey: .name)
                version = try c.decode(String.self, forKey: .version)
                // Een lege `require` schrijft PHP soms als [] in plaats van {}.
                require = (try? c.decodeIfPresent([String: String].self, forKey: .require)) ?? [:]
                dist = try? c.decodeIfPresent(Dist.self, forKey: .dist)
                notificationURL = try? c.decodeIfPresent(String.self, forKey: .notificationURL)
            }
        }
        struct Lock: Decodable {
            let packages: [Package]?
            let packagesDev: [Package]?
            enum CodingKeys: String, CodingKey { case packages, packagesDev = "packages-dev" }
        }
        var read = LockfileRead(ecosystem: "Packagist", source: path, dependencies: [])
        guard let lock = try? JSONDecoder().decode(Lock.self, from: Data(content.utf8)) else { return read }
        var graph: [String: [String]] = [:]
        let all = (lock.packages ?? []).map { ($0, DependencyKind.runtime) } + (lock.packagesDev ?? []).map { ($0, DependencyKind.dev) }
        read.dependencies = all.compactMap { package, kind in
            graph[package.name.lowercased()] = package.require.keys.filter { $0.contains("/") }.map { $0.lowercased() }.sorted()
            read.requirements[package.name.lowercased()] = package.require.reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value }
            guard !package.version.hasPrefix("dev-") else { return nil }
            let version = package.version.droppingVersionPrefix
            guard StackDetector.version(from: version) != nil else { return nil }
            return Dependency(ecosystem: "Packagist", name: package.name, version: version, source: path, workspace: nil, scope: .unknown, kind: kind,
                              registry: registry(package.dist?.url) ?? registry(package.notificationURL))
        }
        read.graph = graph
        return read
    }

    // MARK: - Swift

    /// Package.resolved v1 (`object.pins`, `repositoryURL`) en v2/v3 (`pins`, `location`). OSV kent
    /// Swift-packages als URL zonder schema en ".git": `github.com/apple/swift-nio`. Pins op een
    /// branch of commit (geen `version`) tellen niet. Direct of transitief staat er niet in.
    static func swiftPackages(_ content: String, path: String) -> [Dependency] {
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
}
