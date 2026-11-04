import Foundation

extension DependencyDetector {
    // MARK: - TOML-lockfiles

    /// Eén `[[package]]`-blok: velden op het hoogste niveau en subtabellen (`[package.dependencies]`
    /// → "dependencies"), elk met de ruwe waarde. Arrays over meerdere regels worden één waarde.
    struct TomlPackage {
        var fields: [String: String] = [:]
        var tables: [String: [(key: String, value: String)]] = [:]

        var name: String? { fields["name"].flatMap(TomlPackage.string) }
        var version: String? { fields["version"].flatMap(TomlPackage.string) }

        /// `"x"` → x.
        static func string(_ value: String) -> String? {
            value.wholeMatch(of: /"([^"]*)"/).map { String($0.output.1) }
        }

        /// Alle strings in een array: `["a", "b 1.0"]`.
        static func strings(_ value: String) -> [String] {
            value.matches(of: /"([^"]*)"/).map { String($0.output.1) }
        }

        /// Alle inline tabellen in een array met hun `name` en eventueel `version`.
        static func references(_ value: String) -> [(name: String, version: String?)] {
            // Inline tabellen kunnen zelf tabellen bevatten (`source = { registry = … }`).
            var tables: [String] = []
            var current = ""
            var depth = 0
            var inString = false
            for character in value {
                if character == "\"" { inString.toggle() }
                if !inString, character == "{" { depth += 1 }
                if depth > 0 { current.append(character) }
                if !inString, character == "}", depth > 0 {
                    depth -= 1
                    if depth == 0 {
                        tables.append(current)
                        current = ""
                    }
                }
            }
            return tables.compactMap { table in
                guard let name = table.firstMatch(of: /\bname\s*=\s*"([^"]+)"/)?.output.1 else { return nil }
                return (String(name), table.firstMatch(of: /\bversion\s*=\s*"([^"]+)"/).map { String($0.output.1) })
            }
        }

        /// Map van een eigen project in uv.lock: `{ editable = "." }` of `{ virtual = "packages/api" }`.
        static func localPath(_ source: String) -> String? {
            source.firstMatch(of: /\b(?:editable|virtual)\s*=\s*"([^"]*)"/).map { String($0.output.1) }
        }
    }

    static func tomlPackages(_ content: String) -> [TomlPackage] {
        var packages: [TomlPackage] = []
        var inPackage = false
        var table = ""
        var pending: (key: String, value: String, depth: Int)?
        /// Openende min sluitende haken buiten strings.
        func depth(_ text: String) -> Int {
            var result = 0
            var inString = false
            for character in text {
                if character == "\"" { inString.toggle() }
                if inString { continue }
                if character == "[" || character == "{" { result += 1 }
                if character == "]" || character == "}" { result -= 1 }
            }
            return result
        }
        func store(_ key: String, _ value: String) {
            guard inPackage, !packages.isEmpty else { return }
            if table.isEmpty {
                packages[packages.count - 1].fields[key] = value
            } else {
                packages[packages.count - 1].tables[table, default: []].append((key, value))
            }
        }
        for raw in content.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if var open = pending {
                open.value += " " + line
                open.depth += depth(line)
                if open.depth <= 0 {
                    store(open.key, open.value)
                    pending = nil
                } else {
                    pending = open
                }
                continue
            }
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line == "[[package]]" {
                packages.append(TomlPackage())
                inPackage = true
                table = ""
                continue
            }
            if line.hasPrefix("[") {
                if inPackage, line.hasPrefix("[package."), !line.hasPrefix("[[") {
                    table = String(line.dropFirst("[package.".count).dropLast())
                } else {
                    inPackage = false
                }
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            let open = depth(value)
            if open > 0 { pending = (key, value, open) } else { store(key, value) }
        }
        return packages
    }

    /// Knoop-id "naam@versie"; een verwijzing zonder versie gaat naar het eerste package met die naam.
    private struct TomlIndex {
        let ids: [String]
        let byName: [String: [String]]

        init(_ packages: [(name: String, version: String)], normalize: (String) -> String) {
            ids = packages.map { "\(normalize($0.name))@\($0.version)" }
            byName = Dictionary(grouping: ids, by: { String($0[..<$0.lastIndex(of: "@")!]) })
        }

        func node(_ name: String, _ version: String?, normalize: (String) -> String) -> String? {
            let key = normalize(name)
            if let version, byName[key]?.contains("\(key)@\(version)") == true { return "\(key)@\(version)" }
            return byName[key]?.first
        }
    }

    /// Cargo.lock: `dependencies = ["serde", "syn 2.0.1", …]` per `[[package]]` is de graaf. Crates
    /// zonder `source` zijn de eigen workspace-crates: wat die vragen is direct. Alleen packages met
    /// `source = "registry+…"` worden installs; git-forks staan niet op crates.io. Cargo.lock maakt
    /// geen onderscheid tussen dev en runtime.
    static func cargoLock(_ content: String, path: String) -> [Dependency] {
        let packages = tomlPackages(content).compactMap { package -> (name: String, version: String, source: String?, deps: [String])? in
            guard let name = package.name, let version = package.version else { return nil }
            return (name, version, package.fields["source"].flatMap(TomlPackage.string), package.fields["dependencies"].map(TomlPackage.strings) ?? [])
        }
        let index = TomlIndex(packages.map { ($0.name, $0.version) }, normalize: { $0 })
        var byId: [String: (name: String, version: String, source: String?, deps: [String])] = [:]
        for (id, package) in zip(index.ids, packages) { byId[id] = package }
        let locals = Set(zip(index.ids, packages).filter { $0.1.source == nil }.map(\.0))
        func resolved(_ id: String) -> [String] {
            (byId[id]?.deps ?? []).compactMap { reference in
                let parts = reference.split(separator: " ")
                guard let first = parts.first else { return nil }
                return index.node(String(first), parts.count > 1 ? String(parts[1]) : nil, normalize: { $0 })
            }
        }
        let roots = Set(locals.flatMap(resolved)).subtracting(locals).sorted().map { (node: $0, kind: DependencyKind.runtime) }
        let reach = walk(roots: roots, children: { resolved($0).filter { !locals.contains($0) } }, name: { byId[$0]?.name ?? $0 })
        return zip(index.ids, packages).compactMap { id, package in
            guard package.source?.hasPrefix("registry+") == true else { return nil }
            let found = reach[id]
            let scope: DependencyScope = found.map { $0.via.isEmpty ? .direct : .transitive } ?? (locals.isEmpty ? .unknown : .transitive)
            return Dependency(ecosystem: "crates.io", name: package.name, version: package.version, source: path,
                              workspace: nil, scope: scope, via: found?.via ?? [], registry: registry(package.source))
        }
    }

    /// poetry.lock: `[package.dependencies]` is de graaf; `category = "dev"` (oud) of `groups`
    /// zonder "main" (nieuw) is dev, `optional = true` optioneel. Direct volgt uit pyproject.toml.
    static func poetryLock(_ content: String, path: String) -> LockfileRead {
        var read = LockfileRead(ecosystem: "PyPI", source: path, dependencies: [], kindsKnown: false)
        var graph: [String: [String]] = [:]
        for package in tomlPackages(content) {
            guard let name = package.name, let version = package.version else { continue }
            let key = normalizedPyPIName(name)
            graph[key, default: []] += (package.tables["dependencies"] ?? []).map { normalizedPyPIName($0.key) }
            for (child, value) in package.tables["dependencies"] ?? [] {
                // `"^2.0"`, `{version = ">=1.0", markers = …}` of een lijst daarvan: het eerste bereik.
                if let range = TomlPackage.string(value) ?? value.firstMatch(of: /\bversion\s*=\s*"([^"]+)"/).map({ String($0.output.1) }) {
                    read.requirements[key, default: [:]][normalizedPyPIName(child)] = range
                }
            }
            let category = package.fields["category"].flatMap(TomlPackage.string)
            let groups = package.fields["groups"].map(TomlPackage.strings)
            if category != nil || groups != nil { read.kindsKnown = true }
            let kind: DependencyKind = if category == "dev" || groups.map({ !$0.contains("main") }) == true {
                .dev
            } else if package.fields["optional"] == "true" {
                .optional
            } else {
                .runtime
            }
            // `[package.source]` met `url` bij een eigen index (`type = "legacy"`).
            let index = package.tables["source"]?.first { $0.key == "url" }.flatMap { TomlPackage.string($0.value) }
            read.dependencies.append(Dependency(ecosystem: "PyPI", name: name, version: version, source: path, workspace: nil, scope: .unknown, kind: kind,
                                                registry: registry(index)))
        }
        read.graph = graph
        return read
    }

    /// uv.lock: het project zelf en de leden van een uv-workspace staan erin als package met
    /// `source = { editable = "…" }` of `{ virtual = "…" }`; hun `dependencies` zijn direct
    /// (runtime), `[package.optional-dependencies]` optioneel en `[package.dev-dependencies]` dev.
    /// Elk lid is een eigen workspace (zijn map). De rest volgt via `dependencies`.
    static func uvLock(_ content: String, path: String) -> LockfileRead {
        struct Package {
            let name: String
            let version: String
            let local: String?
            /// `source = { registry = "…" }`.
            let registry: String?
            let edges: [(name: String, version: String?, kind: DependencyKind)]
        }
        let packages = tomlPackages(content).compactMap { package -> Package? in
            guard let name = package.name else { return nil }
            let source = package.fields["source"] ?? ""
            let local = TomlPackage.localPath(source)
            var edges = TomlPackage.references(package.fields["dependencies"] ?? "").map { ($0.name, $0.version, DependencyKind.runtime) }
            edges += (package.tables["optional-dependencies"] ?? []).flatMap { TomlPackage.references($0.value).map { ($0.name, $0.version, DependencyKind.optional) } }
            edges += (package.tables["dev-dependencies"] ?? []).flatMap { TomlPackage.references($0.value).map { ($0.name, $0.version, DependencyKind.dev) } }
            // Het project zelf heeft soms geen versie (dynamic); als knoop telt het toch.
            let index = source.firstMatch(of: /\bregistry\s*=\s*"([^"]+)"/).map { String($0.output.1) }
            return Package(name: name, version: package.version ?? "", local: local, registry: registry(index), edges: edges)
        }
        let index = TomlIndex(packages.map { ($0.name, $0.version) }, normalize: normalizedPyPIName)
        var byId: [String: Package] = [:]
        for (id, package) in zip(index.ids, packages) { byId[id] = package }
        let locals = Set(zip(index.ids, packages).filter { $0.1.local != nil }.map(\.0))
        func edges(_ id: String) -> [(node: String, kind: DependencyKind)] {
            (byId[id]?.edges ?? []).compactMap { edge in
                index.node(edge.name, edge.version, normalize: normalizedPyPIName).flatMap { locals.contains($0) ? nil : ($0, edge.kind) }
            }
        }
        let children = { (id: String) in edges(id).filter { $0.kind == .runtime }.map(\.node) }
        let name = { (id: String) in byId[id]?.name ?? id }

        let base = folder(of: path)
        var result: [Dependency] = []
        var reached: Set<String> = []
        func install(_ id: String, workspace: String, scope: DependencyScope, kind: DependencyKind, via: [String]) {
            guard let package = byId[id], package.local == nil, !package.version.isEmpty else { return }
            result.append(Dependency(ecosystem: "PyPI", name: package.name, version: package.version, source: path,
                                     workspace: workspace, scope: scope, kind: kind, via: via, registry: package.registry))
        }
        for local in locals.sorted() {
            let workspace = join(base, byId[local]?.local ?? "")
            for (id, reach) in walk(roots: edges(local), children: children, name: name) {
                reached.insert(id)
                install(id, workspace: workspace, scope: reach.via.isEmpty ? .direct : .transitive, kind: reach.kind, via: reach.via)
            }
        }
        for id in index.ids where !reached.contains(id) {
            install(id, workspace: base, scope: locals.isEmpty ? .unknown : .transitive, kind: .runtime, via: [])
        }
        var graph: [String: [String]] = [:]
        for id in index.ids {
            guard let package = byId[id] else { continue }
            graph[normalizedPyPIName(package.name), default: []] += children(id).compactMap { byId[$0].map { normalizedPyPIName($0.name) } }
        }
        return LockfileRead(ecosystem: "PyPI", source: path, dependencies: merged(result), graph: graph, kindsKnown: false)
    }
}
