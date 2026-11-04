import Foundation

/// Wat een package.json vraagt, met bereik: yarn.lock zoekt een entry op `naam@bereik`.
struct PackageJSON: Sendable {
    var requests: [(name: String, range: String, kind: DependencyKind)]
    /// Globs uit `workspaces` (lijst of `{ "packages": [...] }`).
    var workspaces: [String]

    init?(_ content: String) {
        struct Raw: Decodable {
            struct Workspaces: Decodable {
                let globs: [String]
                init(from decoder: any Decoder) throws {
                    struct Object: Decodable { let packages: [String]? }
                    let c = try decoder.singleValueContainer()
                    globs = (try? c.decode([String].self)) ?? (try? c.decode(Object.self))?.packages ?? []
                }
            }
            let dependencies: [String: String]?
            let devDependencies: [String: String]?
            let optionalDependencies: [String: String]?
            let workspaces: Workspaces?
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: Data(content.utf8)) else { return nil }
        requests = []
        for (field, kind) in [(raw.dependencies, DependencyKind.runtime), (raw.optionalDependencies, .optional), (raw.devDependencies, .dev)] {
            for (name, range) in (field ?? [:]).sorted(by: { $0.key < $1.key }) { requests.append((name, range, kind)) }
        }
        workspaces = raw.workspaces?.globs ?? []
    }
}

extension DependencyDetector {
    // MARK: - Workspaces

    /// Of `path` (relatief, zonder "./") bij een workspace-glob hoort: `*` is één mapdeel of een
    /// deel ervan, `**` nul of meer mappen.
    static func matches(glob: String, path: String) -> Bool {
        var pattern = glob.hasPrefix("./") ? String(glob.dropFirst(2)) : glob
        while pattern.hasSuffix("/") { pattern.removeLast() }
        let globParts = pattern.split(separator: "/").map(String.init)
        let pathParts = path.split(separator: "/").map(String.init)
        func segment(_ glob: String, _ part: String) -> Bool {
            let regex = "^" + NSRegularExpression.escapedPattern(for: glob).replacingOccurrences(of: "\\*", with: ".*") + "$"
            return part.range(of: regex, options: .regularExpression) != nil
        }
        func match(_ g: Int, _ p: Int) -> Bool {
            if g == globParts.count { return p == pathParts.count }
            if globParts[g] == "**" { return (p...pathParts.count).contains { match(g + 1, $0) } }
            return p < pathParts.count && segment(globParts[g], pathParts[p]) && match(g + 1, p + 1)
        }
        return match(0, 0)
    }

    /// Mappen (relatief aan `base`) van de package.json's die bij de workspace-globs horen;
    /// globs met "!" sluiten uit.
    static func workspaceFolders(_ globs: [String], base: String, folders: some Sequence<String>) -> [String] {
        let include = globs.filter { !$0.hasPrefix("!") }
        let exclude = globs.filter { $0.hasPrefix("!") }.map { String($0.dropFirst()) }
        return folders.compactMap { folder -> String? in
            let relative: String
            if base.isEmpty {
                relative = folder
            } else if folder.hasPrefix(base + "/") {
                relative = String(folder.dropFirst(base.count + 1))
            } else {
                return nil
            }
            guard !relative.isEmpty, include.contains(where: { matches(glob: $0, path: relative) }),
                  !exclude.contains(where: { matches(glob: $0, path: relative) }) else { return nil }
            return relative
        }.sorted()
    }

    /// Naam uit een descriptor: alles voor de eerste "@" na het begin ("@scope/x@^1" → "@scope/x").
    static func descriptorName(_ descriptor: String) -> (name: String, range: String) {
        guard descriptor.count > 1,
              let at = descriptor[descriptor.index(after: descriptor.startIndex)...].firstIndex(of: "@") else { return (descriptor, "") }
        return (String(descriptor[..<at]), String(descriptor[descriptor.index(after: at)...]))
    }

    // MARK: - yarn

    private struct YarnEntry {
        var descriptors: [String]
        var name: String
        var version: String
        var dependencies: [(name: String, range: String)]
        /// Een eigen package (Berry `workspace:`, `link:`, `portal:`); geen install.
        var isLocal: Bool
        /// Map van een Berry-workspace relatief aan de lockfile; "" is de root.
        var workspace: String?
    }

    /// yarn.lock v1 (classic) en Berry (`__metadata`). Een entry heeft één of meer descriptors
    /// (`naam@bereik`), een versie en `dependencies` met bereiken: dat is de graaf. Wat direct is,
    /// komt uit de package.json van de root en van elke workspace (`workspaces`), met de soort;
    /// Berry noemt zijn workspaces zelf, zonder dev of runtime. Peers tellen niet: die levert de ouder.
    static func yarnLock(_ content: String, path: String, packageJSONs: [String: PackageJSON]) -> LockfileRead {
        let tree = Outline.parse(content)
        let berry = tree.contains { $0.key == "__metadata" }
        var entries: [YarnEntry] = []
        for node in tree where node.key != "__metadata" && node.value == nil {
            let descriptors = node.key.split(separator: ",").map { Outline.unquoted($0.trimmingCharacters(in: .whitespaces)) }
            guard let first = descriptors.first, let version = node["version"]?.value else { continue }
            var (name, range) = descriptorName(first)
            var isLocal = false
            var workspace: String?
            if berry, let resolution = node["resolution"]?.value {
                let resolved = descriptorName(resolution)
                name = resolved.name
                if resolved.range.hasPrefix("workspace:") {
                    workspace = String(resolved.range.dropFirst("workspace:".count))
                    if workspace == "." { workspace = "" }
                }
                isLocal = workspace != nil || node["linkType"]?.value == "soft"
            } else if range.hasPrefix("npm:") {
                // Alias: "string-width-cjs@npm:string-width@^4" is string-width op npm.
                let target = descriptorName(String(range.dropFirst(4)))
                if !target.range.isEmpty { name = target.name }
            } else if range.hasPrefix("file:") || range.hasPrefix("link:") {
                isLocal = true
            }
            let dependencies = ["dependencies", "optionalDependencies"].flatMap { node[$0]?.children ?? [] }
                .map { (name: $0.key, range: $0.value ?? "") }
            entries.append(YarnEntry(descriptors: descriptors, name: name, version: version, dependencies: dependencies,
                                     isLocal: isLocal, workspace: workspace))
        }
        var byDescriptor: [String: Int] = [:]
        for (index, entry) in entries.enumerated() {
            for descriptor in entry.descriptors where byDescriptor[descriptor] == nil { byDescriptor[descriptor] = index }
        }
        /// Berry v6 schrijft `lodash: ^4` bij een descriptor `lodash@npm:^4`; v8 schrijft `"npm:^4"`.
        func node(_ name: String, _ range: String) -> String? {
            let index = byDescriptor["\(name)@\(range)"] ?? byDescriptor["\(name)@npm:\(range)"]
            guard let index, !entries[index].isLocal else { return nil }
            return String(index)
        }
        func entryAt(_ node: String) -> YarnEntry? { Int(node).map { entries[$0] } }
        var childCache: [String: [String]] = [:]
        func children(_ id: String) -> [String] {
            if let cached = childCache[id] { return cached }
            let found = (entryAt(id)?.dependencies ?? []).compactMap { node($0.name, $0.range) }
            childCache[id] = found
            return found
        }

        // Importers: de root, de mappen die de workspace-globs van de root vinden, en de
        // workspaces die Berry zelf noemt.
        let base = folder(of: path)
        var importers: Set<String> = []
        if packageJSONs[base] != nil { importers.insert("") }
        importers.formUnion(workspaceFolders(packageJSONs[base]?.workspaces ?? [], base: base, folders: packageJSONs.keys))
        let berryWorkspaces = Dictionary(entries.compactMap { entry in entry.workspace.map { ($0, entry) } }, uniquingKeysWith: { a, _ in a })
        importers.formUnion(berryWorkspaces.keys)

        var read = LockfileRead(ecosystem: "npm", source: path, dependencies: [])
        var reached: Set<String> = []
        for importer in importers.sorted() {
            let requests = packageJSONs[join(base, importer)]?.requests
                ?? berryWorkspaces[importer]?.dependencies.map { ($0.name, $0.range, DependencyKind.runtime) } ?? []
            let roots = requests.compactMap { request in node(request.name, request.range).map { (node: $0, kind: request.kind) } }
            var rootRanges: [String: String] = [:]
            for request in requests {
                if let id = node(request.name, request.range), rootRanges[id] == nil { rootRanges[id] = request.range }
            }
            for (id, reach) in walk(roots: roots, children: children, name: { entryAt($0)?.name ?? $0 }) {
                guard let entry = entryAt(id), isExactVersion(entry.version) else { continue }
                reached.insert(id)
                // Het bereik van de ouder: de descriptor waarmee hij naar deze entry wijst.
                let requested = reach.parent.map { parent in
                    entryAt(parent)?.dependencies.first { node($0.name, $0.range) == id }?.range
                } ?? rootRanges[id]
                read.dependencies.append(Dependency(
                    ecosystem: "npm", name: entry.name, version: entry.version, source: path, workspace: join(base, importer),
                    scope: reach.via.isEmpty ? .direct : .transitive, kind: reach.kind, via: reach.via, requested: requested
                ))
            }
        }
        // Wat geen importer bereikt (geen package.json gelezen, of een bereik dat niet klopt).
        for (index, entry) in entries.enumerated() where !entry.isLocal && !reached.contains(String(index)) && isExactVersion(entry.version) {
            read.dependencies.append(Dependency(
                ecosystem: "npm", name: entry.name, version: entry.version, source: path, workspace: base,
                scope: importers.isEmpty ? .unknown : .transitive
            ))
        }
        read.dependencies = merged(read.dependencies).sorted { ($0.name, $0.version, $0.workspace) < ($1.name, $1.version, $1.workspace) }
        if importers.isEmpty {
            // Zonder package.json beslist later een manifest uit dezelfde map of de repo.
            var graph: [String: [String]] = [:]
            for (index, entry) in entries.enumerated() {
                graph[entry.name, default: []] += children(String(index)).compactMap { entryAt($0)?.name }
            }
            read.graph = graph
            read.kindsKnown = false
        }
        return read
    }

    // MARK: - pnpm

    /// pnpm-lock.yaml v6 tot v9. `importers` (of, in v6 zonder workspace, de root zelf) geeft per
    /// workspace `dependencies`, `devDependencies` en `optionalDependencies` met de versie; de graaf
    /// staat in `packages` (v6) of `snapshots` (v9). Knopen zijn de sleutels met peer-achtervoegsel
    /// (`react-dom@18.2.0(react@18.2.0)`); voor OSV valt dat achtervoegsel weg.
    static func pnpmLock(_ content: String, path: String) -> LockfileRead {
        let tree = Outline.parse(content)
        func top(_ key: String) -> Outline? { tree.first { $0.key == key } }
        var read = LockfileRead(ecosystem: "npm", source: path, dependencies: [])
        guard top("lockfileVersion") != nil else { return read }

        /// v6 begint sleutels en verwijzingen met "/".
        func id(_ key: String) -> String { key.hasPrefix("/") ? String(key.dropFirst()) : key }
        /// Verwijzing naar een knoop: `4.3.4(supports-color@5.5.0)` bij naam debug, of een alias
        /// (`string-width@4.2.3`, v6 `/string-width@4.2.3`). Links naar workspaces tellen niet.
        func reference(_ name: String, _ version: String) -> String? {
            if version.isEmpty || version.hasPrefix("link:") { return nil }
            if version.hasPrefix("/") { return String(version.dropFirst()) }
            let bare = version.split(separator: "(", maxSplits: 1).first.map(String.init) ?? version
            if bare.dropFirst().contains("@") { return version }
            return "\(name)@\(version)"
        }
        var nodes: Set<String> = []
        var edges: [String: [String]] = [:]
        for section in ["packages", "snapshots"] {
            for package in top(section)?.children ?? [] {
                let node = id(package.key)
                nodes.insert(node)
                for field in ["dependencies", "optionalDependencies"] {
                    for dependency in package[field]?.children ?? [] {
                        if let child = reference(dependency.key, dependency["version"]?.value ?? dependency.value ?? "") {
                            if !(edges[node] ?? []).contains(child) { edges[node, default: []].append(child) }
                        }
                    }
                }
            }
        }
        func children(_ node: String) -> [String] { (edges[node] ?? []).filter(nodes.contains) }
        /// `@babel/core@7.24.0(supports-color@5.5.0)` → ("@babel/core", "7.24.0").
        func package(_ node: String) -> (name: String, version: String) {
            let bare = node.split(separator: "(", maxSplits: 1).first.map(String.init) ?? node
            let (name, version) = descriptorName(bare)
            return (name, version)
        }

        let importers = top("importers")?.children ?? [Outline(rawKey: ".", value: nil, children: tree)]
        let base = folder(of: path)
        var reached: Set<String> = []
        for importer in importers {
            var roots: [(node: String, kind: DependencyKind)] = []
            /// v6+ bewaart per importer het bereik uit package.json als `specifier`.
            var specifiers: [String: String] = [:]
            for (field, kind) in [("dependencies", DependencyKind.runtime), ("optionalDependencies", .optional), ("devDependencies", .dev)] {
                for dependency in importer[field]?.children ?? [] {
                    // v6+: `version:` onder de naam; v5 had de versie als waarde.
                    guard let node = reference(dependency.key, dependency["version"]?.value ?? dependency.value ?? ""),
                          nodes.contains(node) else { continue }
                    roots.append((node, kind))
                    if let specifier = dependency["specifier"]?.value, specifiers[node] == nil { specifiers[node] = specifier }
                }
            }
            let workspace = join(base, importer.key == "." ? "" : importer.key)
            for (node, reach) in walk(roots: roots, children: children, name: { package($0).name }) {
                let (name, version) = package(node)
                guard isExactVersion(version) else { continue }
                reached.insert("\(name)@\(version)")
                // De graaf van pnpm bewaart alleen opgeloste versies: een bereik alleen voor directe installs.
                read.dependencies.append(Dependency(
                    ecosystem: "npm", name: name, version: version, source: path, workspace: workspace,
                    scope: reach.via.isEmpty ? .direct : .transitive, kind: reach.kind, via: reach.via,
                    requested: reach.parent == nil ? specifiers[node] : nil
                ))
            }
        }
        // v9 noemt elk package in `packages` zonder peers en in `snapshots` met: een sleutel telt
        // als bereikt als dezelfde naam en versie bereikt is.
        for node in nodes.sorted() {
            let (name, version) = package(node)
            guard isExactVersion(version), reached.insert("\(name)@\(version)").inserted else { continue }
            read.dependencies.append(Dependency(ecosystem: "npm", name: name, version: version, source: path, workspace: base, scope: .transitive))
        }
        read.dependencies = merged(read.dependencies).sorted { ($0.name, $0.version, $0.workspace) < ($1.name, $1.version, $1.workspace) }
        return read
    }
}
