import Foundation

/// Wat één lockfile of manifest oplevert: de installs en, voor lockfiles die zelf niet zeggen wat
/// direct is (composer.lock, poetry.lock, package-lock v1), wie wat vraagt. Met het manifest in
/// dezelfde map bepaalt `DependencyDetector.resolve` daarna scope en via.
struct LockfileRead: Sendable {
    var ecosystem: String
    var source: String
    var dependencies: [Dependency]
    /// Genormaliseerde naam → genormaliseerde namen die dat package vraagt; nil als de lockfile
    /// scope en via zelf al geeft.
    var graph: [String: [String]]? = nil
    /// De lockfile zegt zelf runtime of dev (composer `packages-dev`, npm-vlaggen, poetry-groepen).
    var kindsKnown = true
    /// Wat de lockfile zelf direct noemt (Gemfile.lock `DEPENDENCIES`); het manifest in dezelfde
    /// map geeft dan alleen nog de soort.
    var directNames: [String: DependencyKind]? = nil
}

/// Een manifest (package.json, composer.json, pyproject.toml, Cargo.toml): welke namen het
/// rechtstreeks vraagt en waarvoor.
struct Manifest: Sendable {
    var ecosystem: String
    /// Genormaliseerde naam → soort; bij dubbel telt wat het zwaarst weegt.
    var names: [String: DependencyKind]
}

/// Leest packages met exacte versies voor de CVE-check en het package-overzicht. Versiebereiken
/// (^1.2, >=3) tellen niet: OSV heeft een exacte versie nodig. Elk package wordt een install met
/// workspace, scope, soort en via.
public enum DependencyDetector {
    public static func isRelevant(_ path: String) -> Bool {
        guard let name = path.split(separator: "/").last.map(String.init) else { return false }
        return name == "go.mod" || name == "package-lock.json" || name == "Package.resolved" || name == "composer.lock" || name == "Cargo.lock" || name == "poetry.lock" || name == "uv.lock"
            || isLockfile(name) || name == "Gemfile" || name == "gems.rb"
            || name == "Directory.Packages.props" || name == "Directory.Build.props"
            || name.hasSuffix(".csproj") || name.hasSuffix(".fsproj")
            || (name.hasPrefix("requirements") && name.hasSuffix(".txt"))
    }

    /// Lockfiles (exacte versies, en dus CVE's); VersionCheck haalt ze als eerste op als een repo
    /// meer dan `StackDetector.maxFiles` relevante bestanden heeft.
    static func isLockfile(_ name: String) -> Bool {
        ["yarn.lock", "pnpm-lock.yaml", "packages.lock.json", "Gemfile.lock", "gems.locked",
         "package-lock.json", "composer.lock", "Cargo.lock", "poetry.lock", "uv.lock", "Package.resolved"].contains(name)
    }

    public static func detect(path: String, content: String) -> [Dependency] {
        read(path: path, content: content).dependencies
    }

    static func read(path: String, content: String) -> LockfileRead {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        if name == "go.mod" { return LockfileRead(ecosystem: "Go", source: path, dependencies: goModules(content, path: path)) }
        if name == "package-lock.json" { return npmLock(content, path: path) }
        if name == "composer.lock" { return composerLock(content, path: path) }
        if name == "Package.resolved" { return LockfileRead(ecosystem: "SwiftURL", source: path, dependencies: swiftPackages(content, path: path)) }
        if name == "poetry.lock" { return poetryLock(content, path: path) }
        if name == "uv.lock" { return uvLock(content, path: path) }
        if name == "yarn.lock" { return yarnLock(content, path: path, packageJSONs: [:]) }
        if name == "pnpm-lock.yaml" { return pnpmLock(content, path: path) }
        if name == "packages.lock.json" { return nugetLock(content, path: path) }
        if name == "Gemfile.lock" || name == "gems.locked" { return gemfileLock(content, path: path) }
        if name == "Gemfile" || name == "gems.rb" { return LockfileRead(ecosystem: "RubyGems", source: path, dependencies: []) }
        if name == "Cargo.lock" { return LockfileRead(ecosystem: "crates.io", source: path, dependencies: cargoLock(content, path: path)) }
        if name.hasPrefix("requirements") { return LockfileRead(ecosystem: "PyPI", source: path, dependencies: requirements(content, path: path)) }
        return LockfileRead(ecosystem: "NuGet", source: path, dependencies: nugetPackages(content, path: path))
    }

    // MARK: - Paden

    /// Map van een bestand; "" voor de root. Een Package.resolved in een Xcode-project of -workspace
    /// hoort bij de map van dat project.
    public static func folder(of path: String) -> String {
        var parts = path.split(separator: "/").dropLast()
        if let project = parts.firstIndex(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
            parts = parts[..<project]
        }
        return parts.joined(separator: "/")
    }

    /// "web" + "packages/ui" → "web/packages/ui"; lege delen vallen weg.
    static func join(_ base: String, _ child: String) -> String {
        let trimmed = child.hasPrefix("./") ? String(child.dropFirst(2)) : child
        if trimmed.isEmpty || trimmed == "." { return base }
        return base.isEmpty ? trimmed : "\(base)/\(trimmed)"
    }

    /// Naam zoals het ecosysteem hem vergelijkt.
    static func normalized(_ name: String, ecosystem: String) -> String {
        switch ecosystem {
        case "PyPI": normalizedPyPIName(name)
        case "Packagist": name.lowercased()
        default: name
        }
    }

    /// PyPI-namen vergelijken zoals PEP 503: kleine letters, `_` en `.` worden `-`.
    static func normalizedPyPIName(_ name: String) -> String {
        name.lowercased().replacing(/[-_.]+/, with: "-")
    }

    static func isExactVersion(_ version: String) -> Bool {
        StackDetector.version(from: version) != nil && !version.contains(":")
    }

    // MARK: - Graaf

    struct Reach: Equatable {
        var via: [String]
        var kind: DependencyKind
    }

    /// Kortste keten (breedte eerst) vanaf de directe packages en de zwaarste soort waarmee een
    /// package bereikt wordt: wat via een runtime-package binnenkomt is runtime, ook als het ook via
    /// een dev-package komt. Knopen zijn vrije ids (npm: het pad in de lockfile, Cargo: naam@versie).
    static func walk(
        roots: [(node: String, kind: DependencyKind)],
        children: (String) -> [String],
        name: (String) -> String
    ) -> [String: Reach] {
        let ordered = roots.sorted {
            $0.kind.weight != $1.kind.weight ? $0.kind.weight > $1.kind.weight : name($0.node) < name($1.node)
        }
        var via: [String: [String]] = [:]
        var queue: [String] = []
        for root in ordered where via[root.node] == nil {
            via[root.node] = []
            queue.append(root.node)
        }
        var index = 0
        while index < queue.count {
            let node = queue[index]
            index += 1
            let chain = (via[node] ?? []) + [name(node)]
            for child in children(node) where via[child] == nil {
                via[child] = chain
                queue.append(child)
            }
        }
        var kinds: [String: DependencyKind] = [:]
        for kind in [DependencyKind.runtime, .optional, .dev] {
            var stack = ordered.filter { $0.kind == kind }.map(\.node)
            while let node = stack.popLast() {
                guard kinds[node] == nil else { continue }
                kinds[node] = kind
                stack += children(node)
            }
        }
        return via.reduce(into: [:]) { result, item in
            result[item.key] = Reach(via: item.value, kind: kinds[item.key] ?? .runtime)
        }
    }

    /// Eén install per package, versie en workspace: direct wint van transitief, runtime van dev,
    /// de kortste via blijft. De volgorde van eerste voorkomen blijft.
    static func merged(_ dependencies: [Dependency]) -> [Dependency] {
        var order: [String] = []
        var byKey: [String: Dependency] = [:]
        func rank(_ scope: DependencyScope) -> Int {
            switch scope {
            case .direct: 2
            case .transitive: 1
            case .unknown: 0
            }
        }
        for dependency in dependencies {
            let key = dependency.installKey
            guard let current = byKey[key] else {
                order.append(key)
                byKey[key] = dependency
                continue
            }
            let scope = rank(dependency.scope) > rank(current.scope) ? dependency.scope : current.scope
            let kind = dependency.kind.weight > current.kind.weight ? dependency.kind : current.kind
            let via = scope == .direct ? [] : [current.via, dependency.via].filter { !$0.isEmpty }.min { $0.count < $1.count } ?? []
            byKey[key] = current.with(scope: scope, kind: kind, via: via)
        }
        return order.compactMap { byKey[$0] }
    }

    // MARK: - Go

    /// `require x v1.2.3` en regels binnen `require ( … )`; de "v" valt weg zoals OSV verwacht.
    /// `// indirect` is transitief; go.mod zegt niet via welk package.
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
        let dev: Bool?
        let optional: Bool?
        let requires: [String: String]?
        let dependencies: [String: NpmV1Entry]?
    }

    /// lockfileVersion 2/3 (`packages`) en 1 (`dependencies`). In 2/3 zijn de root (`""`) en de
    /// workspaces (sleutels zonder `node_modules/`) de importers: hun dependencies zijn direct, de
    /// rest volgt via `dependencies` van elk package met npm's opzoekregels (eerst de eigen
    /// `node_modules/`, dan steeds een map hoger). Elke importer is een eigen workspace.
    private static func npmLock(_ content: String, path: String) -> LockfileRead {
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
                    scope: reach.via.isEmpty ? .direct : .transitive, kind: entry.flaggedKind ?? reach.kind, via: reach.via
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
                scope: hasRoot ? .transitive : .unknown, kind: entry.flaggedKind ?? .runtime, via: Array(chain.dropLast())
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
                                             scope: .unknown, kind: kind, via: chain))
                }
                visit(entry.dependencies ?? [:], chain: chain + [name])
            }
        }
        visit(dependencies, chain: [])
        read.dependencies = merged(result).sorted { ($0.name, $0.version) < ($1.name, $1.version) }
        read.graph = graph
    }

    // MARK: - Composer

    /// `packages` is runtime, `packages-dev` dev; de "v" van tags valt weg, branches (`dev-main`)
    /// tellen niet. `require` van elk package is de graaf; direct volgt uit composer.json.
    private static func composerLock(_ content: String, path: String) -> LockfileRead {
        struct Package: Decodable {
            let name: String
            let version: String
            let require: [String: String]
            enum CodingKeys: String, CodingKey { case name, version, require }
            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decode(String.self, forKey: .name)
                version = try c.decode(String.self, forKey: .version)
                // Een lege `require` schrijft PHP soms als [] in plaats van {}.
                require = (try? c.decodeIfPresent([String: String].self, forKey: .require)) ?? [:]
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
            guard !package.version.hasPrefix("dev-") else { return nil }
            let version = package.version.hasPrefix("v") ? String(package.version.dropFirst()) : package.version
            guard StackDetector.version(from: version) != nil else { return nil }
            return Dependency(ecosystem: "Packagist", name: package.name, version: version, source: path, workspace: nil, scope: .unknown, kind: kind)
        }
        read.graph = graph
        return read
    }

    // MARK: - Swift

    /// Package.resolved v1 (`object.pins`, `repositoryURL`) en v2/v3 (`pins`, `location`). OSV kent
    /// Swift-packages als URL zonder schema en ".git": `github.com/apple/swift-nio`. Pins op een
    /// branch of commit (geen `version`) tellen niet. Direct of transitief staat er niet in.
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
    private static func cargoLock(_ content: String, path: String) -> [Dependency] {
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
                              workspace: nil, scope: scope, via: found?.via ?? [])
        }
    }

    /// poetry.lock: `[package.dependencies]` is de graaf; `category = "dev"` (oud) of `groups`
    /// zonder "main" (nieuw) is dev, `optional = true` optioneel. Direct volgt uit pyproject.toml.
    private static func poetryLock(_ content: String, path: String) -> LockfileRead {
        var read = LockfileRead(ecosystem: "PyPI", source: path, dependencies: [], kindsKnown: false)
        var graph: [String: [String]] = [:]
        for package in tomlPackages(content) {
            guard let name = package.name, let version = package.version else { continue }
            let key = normalizedPyPIName(name)
            graph[key, default: []] += (package.tables["dependencies"] ?? []).map { normalizedPyPIName($0.key) }
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
            read.dependencies.append(Dependency(ecosystem: "PyPI", name: name, version: version, source: path, workspace: nil, scope: .unknown, kind: kind))
        }
        read.graph = graph
        return read
    }

    /// uv.lock: het project zelf en de leden van een uv-workspace staan erin als package met
    /// `source = { editable = "…" }` of `{ virtual = "…" }`; hun `dependencies` zijn direct
    /// (runtime), `[package.optional-dependencies]` optioneel en `[package.dev-dependencies]` dev.
    /// Elk lid is een eigen workspace (zijn map). De rest volgt via `dependencies`.
    private static func uvLock(_ content: String, path: String) -> LockfileRead {
        struct Package {
            let name: String
            let version: String
            let local: String?
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
            return Package(name: name, version: package.version ?? "", local: local, edges: edges)
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
                                     workspace: workspace, scope: scope, kind: kind, via: via))
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

    // MARK: - Manifesten zonder lockfile

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

    // MARK: - Manifesten

    /// Namen die een manifest rechtstreeks vraagt, voor lockfiles die dat zelf niet zeggen
    /// (composer.lock, poetry.lock, package-lock v1).
    public static func directNames(path: String, content: String) -> (ecosystem: String, names: Set<String>)? {
        manifest(path: path, content: content).map { ($0.ecosystem, Set($0.names.keys)) }
    }

    static func manifest(path: String, content: String) -> Manifest? {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        var names: [String: DependencyKind] = [:]
        func add(_ name: String, _ kind: DependencyKind) {
            if let current = names[name], current.weight >= kind.weight { return }
            names[name] = kind
        }
        switch name {
        case "package.json":
            struct PackageJSON: Decodable {
                let dependencies: [String: String]?
                let devDependencies: [String: String]?
                let optionalDependencies: [String: String]?
            }
            guard let manifest = try? JSONDecoder().decode(PackageJSON.self, from: Data(content.utf8)) else { return nil }
            for (field, kind) in [(manifest.dependencies, DependencyKind.runtime), (manifest.devDependencies, .dev), (manifest.optionalDependencies, .optional)] {
                for key in (field ?? [:]).keys { add(key, kind) }
            }
            return Manifest(ecosystem: "npm", names: names)
        case "composer.json":
            struct ComposerJSON: Decodable {
                let require: [String: String]?
                let requireDev: [String: String]?
                enum CodingKeys: String, CodingKey { case require, requireDev = "require-dev" }
            }
            guard let manifest = try? JSONDecoder().decode(ComposerJSON.self, from: Data(content.utf8)) else { return nil }
            for (field, kind) in [(manifest.require, DependencyKind.runtime), (manifest.requireDev, .dev)] {
                for key in (field ?? [:]).keys where key != "php" && !key.hasPrefix("ext-") && key.contains("/") {
                    add(key.lowercased(), kind)
                }
            }
            return Manifest(ecosystem: "Packagist", names: names)
        case "pyproject.toml":
            for (key, kind) in pyprojectNames(content) { add(key, kind) }
            return Manifest(ecosystem: "PyPI", names: names)
        case "Cargo.toml":
            for (key, kind) in cargoDependencies(content) { add(key, kind) }
            return Manifest(ecosystem: "crates.io", names: names)
        case "Gemfile", "gems.rb":
            for (key, kind) in gemfileNames(content) { add(key, kind) }
            return Manifest(ecosystem: "RubyGems", names: names)
        default:
            return nil
        }
    }

    /// `[project] dependencies = [ "pakket>=1", … ]` (runtime), `[project.optional-dependencies]`
    /// (optioneel), `[dependency-groups]` en `[tool.uv] dev-dependencies` (dev), en de sleutels van
    /// `[tool.poetry.dependencies]` (zonder python) en `[tool.poetry.group.<g>.dependencies]` (dev,
    /// behalve main).
    private static func pyprojectNames(_ content: String) -> [(String, DependencyKind)] {
        var names: [(String, DependencyKind)] = []
        var section = ""
        var arrayKind: DependencyKind?
        for raw in content.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && arrayKind == nil {
                section = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                continue
            }
            if arrayKind == nil, line.contains("[") {
                let key = line.split(separator: "=", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) ?? ""
                switch section {
                case "project" where key == "dependencies": arrayKind = .runtime
                case "project.optional-dependencies": arrayKind = .optional
                case "dependency-groups": arrayKind = .dev
                case "tool.uv" where key == "dev-dependencies": arrayKind = .dev
                default: break
                }
            }
            if let kind = arrayKind {
                for match in line.matches(of: /"([A-Za-z0-9][A-Za-z0-9._-]*)/) where !line.contains("include-group") {
                    names.append((normalizedPyPIName(String(match.output.1)), kind))
                }
                // Extras (`requests[socks]`) staan binnen de quotes; alleen een "]" daarbuiten sluit de lijst.
                if line.replacing(/"[^"]*"/, with: "").contains("]") { arrayKind = nil }
                continue
            }
            let poetryKind: DependencyKind? = if section == "tool.poetry.dependencies" || section == "tool.poetry.group.main.dependencies" {
                .runtime
            } else if section == "tool.poetry.dev-dependencies" || section.hasPrefix("tool.poetry.group.") && section.hasSuffix(".dependencies") {
                .dev
            } else {
                nil
            }
            if let poetryKind, let m = line.firstMatch(of: /^([A-Za-z0-9][A-Za-z0-9._-]*)\s*=/) {
                let name = String(m.output.1)
                if name != "python" { names.append((normalizedPyPIName(name), poetryKind)) }
            }
        }
        return names
    }

    /// Crate-namen uit `[dependencies]`, `[build-dependencies]` en `[workspace.dependencies]`
    /// (runtime), `[dev-dependencies]` (dev) en `[target.'…'.dependencies]` (sleutels), plus tabellen
    /// als `[dependencies.serde]` (naam in de kop).
    private static func cargoDependencies(_ content: String) -> [(String, DependencyKind)] {
        let kinds: [(String, DependencyKind)] = [("dependencies", .runtime), ("dev-dependencies", .dev), ("build-dependencies", .runtime)]
        var names: [(String, DependencyKind)] = []
        var current: DependencyKind?
        for raw in content.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                let section = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                current = kinds.first { section == $0.0 || section.hasSuffix(".\($0.0)") }?.1
                if current == nil, let kind = kinds.first(where: { section.hasPrefix("\($0.0).") }) {
                    names.append((String(section.dropFirst(kind.0.count + 1)), kind.1))
                }
                continue
            }
            if let current, let m = line.firstMatch(of: /^([A-Za-z0-9_-]+)\s*=/) {
                names.append((String(m.output.1), current))
            }
        }
        return names
    }

    // MARK: - Samenvoegen

    /// Alle installs uit de bestanden van één repo (lockfiles en manifesten, andere bestanden tellen
    /// niet), plus de direct gevraagde namen per ecosysteem over de hele repo. Pas na alle bestanden
    /// samengevoegd: een manifest kan na zijn lockfile komen. Zelfde package en versie uit twee
    /// bestanden in dezelfde map is één install (eerste bron wint).
    public static func installs(_ files: [(path: String, content: String)]) -> (dependencies: [Dependency], manifests: [String: Set<String>]) {
        var reads: [LockfileRead] = []
        var repoWide: [String: Set<String>] = [:]
        /// "ecosysteem|map" → manifest, voor scope en via van lockfiles in dezelfde map.
        var manifests: [String: Manifest] = [:]
        /// Map → package.json met bereiken en workspaces, voor yarn.lock.
        var packageJSONs: [String: PackageJSON] = [:]
        for (path, content) in files where path.split(separator: "/").last == "package.json" {
            packageJSONs[folder(of: path)] = PackageJSON(content)
        }
        for (path, content) in files {
            if let manifest = manifest(path: path, content: content) {
                repoWide[manifest.ecosystem, default: []].formUnion(manifest.names.keys)
                manifests["\(manifest.ecosystem)|\(folder(of: path))", default: Manifest(ecosystem: manifest.ecosystem, names: [:])].names
                    .merge(manifest.names) { $0.weight >= $1.weight ? $0 : $1 }
            }
            guard isRelevant(path) else { continue }
            if path.split(separator: "/").last == "yarn.lock" {
                reads.append(yarnLock(content, path: path, packageJSONs: packageJSONs))
            } else {
                reads.append(read(path: path, content: content))
            }
        }
        return (resolve(reads, manifests: manifests, repoWide: repoWide), repoWide)
    }

    /// Scope, soort en via voor lockfiles die dat zelf niet zeggen, met het manifest uit dezelfde
    /// map (`manifests`: "ecosysteem|map" → manifest). Zonder zo'n manifest beslissen de namen van
    /// alle manifesten van de repo (`repoWide`), zoals vroeger; Swift-pins blijven onbekend.
    /// Daarna één install per package, versie en workspace.
    static func resolve(_ reads: [LockfileRead], manifests: [String: Manifest], repoWide: [String: Set<String>]) -> [Dependency] {
        var result: [Dependency] = []
        for read in reads {
            var dependencies = read.dependencies
            let local = manifests["\(read.ecosystem)|\(folder(of: read.source))"]
            let manifest = read.directNames.map { names in
                Manifest(ecosystem: read.ecosystem, names: names.reduce(into: [:]) { $0[$1.key] = local?.names[$1.key] ?? $1.value })
            } ?? local
            if let graph = read.graph, dependencies.contains(where: { $0.scope == .unknown }), let manifest {
                let normalize = { (name: String) in normalized(name, ecosystem: read.ecosystem) }
                var display: [String: String] = [:]
                for dependency in dependencies { display[normalize(dependency.name)] = dependency.name }
                let roots = manifest.names.filter { graph[$0.key] != nil || display[$0.key] != nil }.map { (node: $0.key, kind: $0.value) }
                let reach = walk(roots: roots, children: { graph[$0] ?? [] }, name: { display[$0] ?? $0 })
                dependencies = dependencies.map { dependency in
                    guard dependency.scope == .unknown else { return dependency }
                    // Genest in de lockfile (npm v1): er is alleen een eigen kopie omdat de ouder een
                    // andere versie nodig heeft, dus transitief, via de keten naar die ouder.
                    if let parent = dependency.via.first {
                        let head = reach[normalize(parent)]
                        return dependency.with(scope: .transitive, kind: read.kindsKnown ? nil : head?.kind, via: (head?.via ?? []) + dependency.via)
                    }
                    guard let found = reach[normalize(dependency.name)] else { return dependency.with(scope: .transitive, via: []) }
                    return dependency.with(scope: found.via.isEmpty ? .direct : .transitive, kind: read.kindsKnown ? nil : found.kind, via: found.via)
                }
            }
            result += dependencies.map { dependency in
                guard dependency.scope == .unknown, let names = repoWide[dependency.ecosystem],
                      names.contains(normalized(dependency.name, ecosystem: dependency.ecosystem)) else { return dependency }
                return dependency.with(scope: .direct, via: [])
            }
        }
        return merged(result)
    }

    /// Packages die een repo ergens direct gebruikt, één per (ecosysteem, naam) met al hun installs
    /// (ook transitieve en andere versies), op volgorde van de eerste directe install. Een install
    /// met onbekende scope telt als direct als een manifest de naam noemt; Swift-pins altijd (geen manifest).
    public static func direct(_ dependencies: [Dependency], manifests: [String: Set<String>]) -> [PackageUse] {
        func isDirect(_ dependency: Dependency) -> Bool {
            switch dependency.scope {
            case .direct: return true
            case .transitive: return false
            case .unknown:
                if dependency.ecosystem == "SwiftURL" { return true }
                guard let names = manifests[dependency.ecosystem] else { return false }
                return names.contains(normalized(dependency.name, ecosystem: dependency.ecosystem))
            }
        }
        var order: [String] = []
        var packages: [String: (ecosystem: String, name: String, installs: [PackageInstall])] = [:]
        var direct: Set<String> = []
        for dependency in dependencies {
            let key = "\(dependency.ecosystem):\(dependency.name)"
            let counts = isDirect(dependency)
            let install = counts && dependency.scope == .unknown ? dependency.with(scope: .direct).install : dependency.install
            if packages[key] == nil { packages[key] = (dependency.ecosystem, dependency.name, []) }
            if packages[key]?.installs.contains(install) == false { packages[key]?.installs.append(install) }
            if counts, direct.insert(key).inserted { order.append(key) }
        }
        return order.compactMap { key in packages[key].map { PackageUse(ecosystem: $0.ecosystem, name: $0.name, installs: $0.installs) } }
    }
}
