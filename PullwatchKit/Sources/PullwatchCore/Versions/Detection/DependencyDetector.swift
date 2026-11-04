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
    /// Bereiken die de lockfile zelf bewaart: genormaliseerde naam van de ouder → genormaliseerde
    /// naam → bereik (composer `require`, poetry `[package.dependencies]`, Gemfile.lock-specs).
    var requirements: [String: [String: String]] = [:]
    /// Bereiken van wat de lockfile direct noemt (Gemfile.lock `DEPENDENCIES`).
    var directRanges: [String: String] = [:]
}

/// Een manifest (package.json, composer.json, pyproject.toml, Cargo.toml): welke namen het
/// rechtstreeks vraagt en waarvoor.
struct Manifest: Sendable {
    var ecosystem: String
    /// Genormaliseerde naam → soort; bij dubbel telt wat het zwaarst weegt.
    var names: [String: DependencyKind]
    /// Genormaliseerde naam → gevraagd bereik zoals geschreven; bij dubbel het eerste.
    var ranges: [String: String] = [:]
}

/// Leest packages met exacte versies voor de CVE-check en het package-overzicht. Versiebereiken
/// (^1.2, >=3) tellen niet als versie: OSV heeft een exacte versie nodig. Elk package wordt een
/// install met workspace, scope, soort, via en het gevraagde bereik (`Dependency.requested`).
enum DependencyDetector {
    static func isRelevant(_ path: String) -> Bool {
        guard let name = path.split(separator: "/").last.map(String.init) else { return false }
        return name == "go.mod" || name == "package-lock.json" || name == "Package.resolved" || name == "composer.lock" || name == "Cargo.lock" || name == "poetry.lock" || name == "uv.lock"
            || name == "Cargo.toml" || isLockfile(name) || name == "Gemfile" || name == "gems.rb"
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

    static func detect(path: String, content: String) -> [Dependency] {
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
        if name == "Cargo.toml" { return LockfileRead(ecosystem: "crates.io", source: path, dependencies: []) }
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
        /// De knoop waarvandaan dit package (breedte eerst) het eerst bereikt werd; nil voor een root.
        var parent: String? = nil
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
        var parents: [String: String] = [:]
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
                parents[child] = node
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
            result[item.key] = Reach(via: item.value, kind: kinds[item.key] ?? .runtime, parent: parents[item.key])
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
            // Het bereik hoort bij wat wint: de directe install, anders de eerste die er een heeft.
            let requested = rank(dependency.scope) > rank(current.scope)
                ? dependency.requested ?? current.requested : current.requested ?? dependency.requested
            byKey[key] = current.with(scope: scope, kind: kind, via: via, requested: requested)
        }
        return order.compactMap { byKey[$0] }
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
        /// Map → Cargo.toml: een lid erft eisen uit de workspace-root, dus pas na alle bestanden.
        var cargo: [String: CargoManifest] = [:]
        for (path, content) in files {
            if path.split(separator: "/").last == "Cargo.toml" {
                cargo[folder(of: path)] = cargoManifest(content)
                continue
            }
            if let manifest = manifest(path: path, content: content) {
                repoWide[manifest.ecosystem, default: []].formUnion(manifest.names.keys)
                let key = "\(manifest.ecosystem)|\(folder(of: path))"
                manifests[key, default: Manifest(ecosystem: manifest.ecosystem, names: [:])].names
                    .merge(manifest.names) { $0.weight >= $1.weight ? $0 : $1 }
                manifests[key]?.ranges.merge(manifest.ranges) { first, _ in first }
            }
            guard isRelevant(path) else { continue }
            if path.split(separator: "/").last == "yarn.lock" {
                reads.append(yarnLock(content, path: path, packageJSONs: packageJSONs))
            } else {
                reads.append(read(path: path, content: content))
            }
        }
        let cargoDeclarations = cargoDeclarations(cargo)
        for (folder, declarations) in cargoDeclarations {
            guard let manifest = cargo[folder] else { continue }
            let names = cargoManifestNames(manifest, declarations: declarations)
            repoWide["crates.io", default: []].formUnion(names.names.keys)
            manifests["crates.io|\(folder)"] = names
        }
        let resolved = resolve(reads, manifests: manifests, repoWide: repoWide).map { dependency -> Dependency in
            // Cargo: de eis uit elke Cargo.toml onder de lockfile, met geërfde eisen van de workspace.
            guard dependency.ecosystem == "crates.io", dependency.scope == .direct, !cargo.isEmpty else { return dependency }
            let found = cargoRequirement(of: dependency, lockfolder: folder(of: dependency.source), declarations: cargoDeclarations, manifests: cargo)
            return dependency.with(kind: found.kind, requested: .some(found.requested ?? dependency.requested))
        }
        return (resolved, repoWide)
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
                    let key = normalize(dependency.name)
                    guard let found = reach[key] else { return dependency.with(scope: .transitive, via: []) }
                    let requested: String? = dependency.requested ?? found.parent.flatMap { read.requirements[$0]?[key] }
                    return dependency.with(scope: found.via.isEmpty ? .direct : .transitive, kind: read.kindsKnown ? nil : found.kind, via: found.via,
                                           requested: .some(requested))
                }
            }
            result += dependencies.map { dependency in
                guard dependency.scope == .unknown, let names = repoWide[dependency.ecosystem],
                      names.contains(normalized(dependency.name, ecosystem: dependency.ecosystem)) else { return dependency }
                return dependency.with(scope: .direct, via: [])
            }.map { dependency in
                guard dependency.requested == nil, dependency.scope != .transitive else { return dependency }
                return dependency.with(requested: manifestRange(of: dependency, lockfile: read, manifests: manifests))
            }
        }
        return merged(result)
    }

    /// Het bereik dat een manifest voor een directe install vraagt: eerst dat in de workspace van
    /// de install, dan dat naast de lockfile, dan wat de lockfile zelf noemt (Gemfile.lock), en
    /// anders, als alle manifesten van de repo hetzelfde vragen, dat.
    static func manifestRange(of dependency: Dependency, lockfile read: LockfileRead, manifests: [String: Manifest]) -> String? {
        let key = normalized(dependency.name, ecosystem: dependency.ecosystem)
        for folder in [dependency.workspace, folder(of: read.source)] {
            if let range = manifests["\(dependency.ecosystem)|\(folder)"]?.ranges[key] { return range }
        }
        if let range = read.directRanges[key] { return range }
        let all = Set(manifests.values.filter { $0.ecosystem == dependency.ecosystem }.compactMap { $0.ranges[key] })
        return all.count == 1 ? all.first : nil
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
