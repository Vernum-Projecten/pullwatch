import Foundation

extension DependencyDetector {
    // MARK: - npm

    private struct NpmEntry: Decodable {
        let name: String?
        let version: String?
        let dependencies: [String: String]?
        let devDependencies: [String: String]?
        let optionalDependencies: [String: String]?
        let peerDependencies: [String: String]?
        let dev: Bool?
        let optional: Bool?
        let devOptional: Bool?
        let link: Bool?
        /// Waar npm het package haalde: de tarball-URL in het register.
        let resolved: String?

        /// Wat de lockfile zelf over de soort zegt; nil zonder vlag.
        var flaggedKind: DependencyKind? {
            if devOptional == true || dev == true { return .dev }
            if optional == true { return .optional }
            return nil
        }
    }

    /// lockfileVersion 1 (`dependencies`, genest).
    private struct NpmV1Entry: Decodable {
        let version: String?
        let resolved: String?
        let dev: Bool?
        let optional: Bool?
        let requires: [String: String]?
        let dependencies: [String: NpmV1Entry]?
    }

    /// lockfileVersion 2/3 (`packages`) en 1 (`dependencies`). In 2/3 zijn de root (`""`) en de
    /// workspaces (sleutels zonder `node_modules/`) de importers: hun dependencies zijn direct, de
    /// rest volgt via `dependencies` van elk package met npm's opzoekregels (eerst de eigen
    /// `node_modules/`, dan steeds een map hoger). Elke importer is een eigen workspace.
    static func npmLock(_ content: String, path: String) -> LockfileRead {
        struct Lock: Decodable {
            let packages: [String: NpmEntry]?
            let dependencies: [String: NpmV1Entry]?
        }
        var read = LockfileRead(ecosystem: "npm", source: path, dependencies: [])
        guard let lock = try? JSONDecoder().decode(Lock.self, from: Data(content.utf8)) else { return read }
        let base = folder(of: path)
        guard let packages = lock.packages else {
            npmV1(lock.dependencies ?? [:], path: path, base: base, into: &read)
            return read
        }

        func name(_ key: String) -> String {
            if let name = packages[key]?.name, key.contains("node_modules/") { return name }
            guard let range = key.range(of: "node_modules/", options: .backwards) else { return key }
            return String(key[range.upperBound...])
        }
        func resolve(_ dependency: String, from key: String) -> String? {
            var current = key
            while true {
                let candidate = current.isEmpty ? "node_modules/\(dependency)" : "\(current)/node_modules/\(dependency)"
                if let entry = packages[candidate] { return entry.link == true ? nil : candidate }
                if current.isEmpty { return nil }
                if let range = current.range(of: "/node_modules/", options: .backwards) {
                    current = String(current[..<range.lowerBound])
                } else {
                    current = ""
                }
            }
        }
        /// Het bereik waarmee `parent` het package op `key` vraagt (naam zoals in de lockfile, ook bij een alias).
        func requested(by parent: String, _ key: String) -> String? {
            guard let entry = packages[parent], let range = key.range(of: "node_modules/", options: .backwards) else { return nil }
            let dependency = String(key[range.upperBound...])
            return entry.dependencies?[dependency] ?? entry.optionalDependencies?[dependency] ?? entry.peerDependencies?[dependency]
                ?? entry.devDependencies?[dependency]
        }
        var childCache: [String: [String]] = [:]
        func children(_ key: String) -> [String] {
            if let cached = childCache[key] { return cached }
            guard let entry = packages[key] else { return [] }
            let names = [entry.dependencies, entry.optionalDependencies, entry.peerDependencies].compactMap { $0?.keys }.joined()
            let found = Set(names).sorted().compactMap { resolve($0, from: key) }
            childCache[key] = found
            return found
        }

        var reached: Set<String> = []
        var result: [Dependency] = []
        let importers = packages.keys.filter { !$0.contains("node_modules/") }.sorted()
        for importer in importers {
            guard let entry = packages[importer] else { continue }
            var roots: [(node: String, kind: DependencyKind)] = []
            for (field, kind) in [(entry.dependencies, DependencyKind.runtime), (entry.optionalDependencies, .optional), (entry.devDependencies, .dev)] {
                for dependency in (field ?? [:]).keys.sorted() {
                    if let node = resolve(dependency, from: importer) { roots.append((node, kind)) }
                }
            }
            let workspace = join(base, importer)
            for (key, reach) in walk(roots: roots, children: children, name: name) {
                guard let entry = packages[key], let version = entry.version, isExactVersion(version) else { continue }
                reached.insert(key)
                result.append(Dependency(
                    ecosystem: "npm", name: name(key), version: version, source: path, workspace: workspace,
                    scope: reach.via.isEmpty ? .direct : .transitive, kind: entry.flaggedKind ?? reach.kind, via: reach.via,
                    requested: requested(by: reach.parent ?? importer, key), registry: registry(entry.resolved)
                ))
            }
        }
        // Wat geen importer bereikt (graaf onvolledig, bv. zonder `dependencies` per package):
        // workspace en via uit het pad zelf.
        let hasRoot = packages[""] != nil
        for (key, entry) in packages where key.contains("node_modules/") && !reached.contains(key) {
            guard entry.link != true, let version = entry.version, isExactVersion(version),
                  let first = key.range(of: "node_modules/") else { continue }
            let owner = String(key[..<first.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let chain = key[first.upperBound...].components(separatedBy: "/node_modules/")
            result.append(Dependency(
                ecosystem: "npm", name: name(key), version: version, source: path, workspace: join(base, owner),
                scope: hasRoot ? .transitive : .unknown, kind: entry.flaggedKind ?? .runtime, via: Array(chain.dropLast()),
                registry: registry(entry.resolved)
            ))
        }
        read.dependencies = merged(result).sorted { ($0.name, $0.version, $0.workspace) < ($1.name, $1.version, $1.workspace) }
        return read
    }

    /// v1 zegt niet wat de root vraagt: scope blijft onbekend tot het manifest het zegt; de graaf
    /// komt uit `requires`.
    private static func npmV1(_ dependencies: [String: NpmV1Entry], path: String, base: String, into read: inout LockfileRead) {
        var result: [Dependency] = []
        var graph: [String: [String]] = [:]
        func visit(_ entries: [String: NpmV1Entry], chain: [String]) {
            for (name, entry) in entries.sorted(by: { $0.key < $1.key }) {
                graph[name, default: []] += (entry.requires ?? [:]).keys.sorted().filter { !(graph[name] ?? []).contains($0) }
                if let version = entry.version, isExactVersion(version) {
                    let kind: DependencyKind = entry.dev == true ? .dev : entry.optional == true ? .optional : .runtime
                    result.append(Dependency(ecosystem: "npm", name: name, version: version, source: path, workspace: base,
                                             scope: .unknown, kind: kind, via: chain, registry: registry(entry.resolved)))
                }
                visit(entry.dependencies ?? [:], chain: chain + [name])
            }
        }
        visit(dependencies, chain: [])
        read.dependencies = merged(result).sorted { ($0.name, $0.version) < ($1.name, $1.version) }
        read.graph = graph
    }
}
