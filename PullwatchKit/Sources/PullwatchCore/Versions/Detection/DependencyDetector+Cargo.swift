import Foundation

/// Eén dependency zoals een Cargo.toml hem vraagt
/// (https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html).
struct CargoDeclaration: Hashable, Sendable {
    /// De sleutel in het manifest; bij een hernoemd package de nieuwe naam.
    var key: String
    /// `package = "…"`: de echte naam op crates.io als de sleutel een andere naam is.
    var package: String?
    var kind: DependencyKind
    /// De versie-eis zoals geschreven; nil zonder (een pad of git zonder versie, of geërfd).
    var requirement: String?
    /// `workspace = true`: de eis komt uit `[workspace.dependencies]` van de workspace-root.
    var inherits = false
    /// `path = …` of `git = …`: zonder versie-eis geen package van crates.io.
    var isPathOrGit = false

    /// De naam zoals Cargo.lock hem noemt.
    var crate: String { package ?? key }
}

/// Wat een Cargo.toml over dependencies zegt.
struct CargoManifest: Hashable, Sendable {
    /// `[dependencies]`, `[dev-dependencies]`, `[build-dependencies]`, ook per target en als eigen
    /// tabel (`[dependencies.serde]`).
    var declarations: [CargoDeclaration] = []
    /// `[workspace.dependencies]`, op sleutel.
    var workspace: [String: CargoDeclaration] = [:]
    /// Het manifest heeft een `[workspace]`-tabel: het is de root van een workspace.
    var isWorkspaceRoot = false

    /// De declaraties met de geërfde eisen ingevuld uit `root` (de workspace-root, of dit manifest zelf).
    func resolved(root: CargoManifest?) -> [CargoDeclaration] {
        declarations.map { declaration in
            guard declaration.inherits else { return declaration }
            var result = declaration
            let inherited = (root ?? self).workspace[declaration.key]
            result.package = declaration.package ?? inherited?.package
            result.requirement = inherited?.requirement
            result.isPathOrGit = inherited?.isPathOrGit ?? false
            return result
        }
    }
}

extension DependencyDetector {
    // MARK: - Cargo.toml lezen

    private static let cargoTables: [String: DependencyKind] = [
        "dependencies": .runtime, "build-dependencies": .runtime, "build_dependencies": .runtime,
        "dev-dependencies": .dev, "dev_dependencies": .dev,
    ]

    /// Leest de dependencies van een Cargo.toml: per regel, met gestippelde sleutels
    /// (`serde.workspace = true`), inline tabellen en eigen tabellen per dependency. Commentaar na
    /// `#` telt niet.
    static func cargoManifest(_ content: String) -> CargoManifest {
        var manifest = CargoManifest()
        /// Waar de regels nu heen gaan: een tabel met dependencies (soort, workspace) of één
        /// dependency in een eigen tabel.
        var table: (kind: DependencyKind, isWorkspace: Bool)?
        var single: (key: String, kind: DependencyKind, isWorkspace: Bool)?
        func update(_ key: String, kind: DependencyKind, isWorkspace: Bool, _ change: (inout CargoDeclaration) -> Void) {
            if isWorkspace {
                var declaration = manifest.workspace[key] ?? CargoDeclaration(key: key, kind: .runtime)
                change(&declaration)
                manifest.workspace[key] = declaration
            } else if let index = manifest.declarations.lastIndex(where: { $0.key == key && $0.kind == kind }) {
                change(&manifest.declarations[index])
            } else {
                var declaration = CargoDeclaration(key: key, kind: kind)
                change(&declaration)
                manifest.declarations.append(declaration)
            }
        }
        /// Een waarde over meer regels (een array, ook binnen een inline tabel) wordt één regel.
        var pending = ""
        for raw in content.split(whereSeparator: \.isNewline) {
            let part = withoutComment(String(raw)).trimmingCharacters(in: .whitespaces)
            let line = pending.isEmpty ? part : pending + " " + part
            if !line.hasPrefix("["), openBrackets(line) > 0 {
                pending = line
                continue
            }
            pending = ""
            if line.isEmpty { continue }
            if line.hasPrefix("[") {
                table = nil
                single = nil
                let parts = keyParts(line.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")))
                if parts == ["workspace"] { manifest.isWorkspaceRoot = true }
                guard let index = parts.firstIndex(where: { cargoTables[$0] != nil }), let kind = cargoTables[parts[index]] else { continue }
                let prefix = Array(parts[..<index])
                let isWorkspace = prefix == ["workspace"]
                // Alleen de root, een target (`target.'cfg(unix)'`) of de workspace.
                guard prefix.isEmpty || isWorkspace || (prefix.count == 2 && prefix[0] == "target") else { continue }
                if isWorkspace { manifest.isWorkspaceRoot = true }
                let rest = parts[(index + 1)...]
                if rest.isEmpty {
                    table = (kind, isWorkspace)
                } else if rest.count == 1, let key = rest.first {
                    single = (key, kind, isWorkspace)
                    update(key, kind: kind, isWorkspace: isWorkspace) { _ in }
                }
                continue
            }
            // Een element van een array over meerdere regels (`"derive",`) is geen sleutel.
            guard !line.hasSuffix(","), let equals = line.firstIndex(of: "=") else { continue }
            let key = keyParts(String(line[..<equals]))
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if let single, key.count == 1, let field = key.first {
                update(single.key, kind: single.kind, isWorkspace: single.isWorkspace) { apply(field: field, value: value, to: &$0) }
            } else if let table, let name = key.first {
                if key.count == 1 {
                    update(name, kind: table.kind, isWorkspace: table.isWorkspace) { apply(value: value, to: &$0) }
                } else if key.count == 2 {
                    update(name, kind: table.kind, isWorkspace: table.isWorkspace) { apply(field: key[1], value: value, to: &$0) }
                }
            }
        }
        return manifest
    }

    /// `serde = "1.0"` of `serde = { version = "1.0", package = "…", workspace = true, path = "…" }`.
    private static func apply(value: String, to declaration: inout CargoDeclaration) {
        if let text = TomlPackage.string(value) {
            declaration.requirement = text
            return
        }
        guard value.hasPrefix("{") else { return }
        for (field, fieldValue) in inlineFields(value) { apply(field: field, value: fieldValue, to: &declaration) }
    }

    /// Eén veld van een dependency (`version`, `package`, `workspace`, `path`, `git`).
    private static func apply(field: String, value: String, to declaration: inout CargoDeclaration) {
        switch field {
        case "version": declaration.requirement = TomlPackage.string(value)
        case "package": declaration.package = TomlPackage.string(value)
        case "workspace": declaration.inherits = value.hasPrefix("true")
        case "path", "git": declaration.isPathOrGit = true
        default: break
        }
    }

    /// De velden van een inline tabel op het hoogste niveau: `{ version = "1", features = ["a"] }`.
    static func inlineFields(_ value: String) -> [(String, String)] {
        var body = Substring(value.trimmingCharacters(in: .whitespaces))
        guard body.hasPrefix("{"), body.hasSuffix("}") else { return [] }
        body = body.dropFirst().dropLast()
        var items: [String] = []
        var current = ""
        var depth = 0
        var inString = false
        for character in body {
            if character == "\"" { inString.toggle() }
            if !inString {
                if character == "[" || character == "{" { depth += 1 }
                if character == "]" || character == "}" { depth -= 1 }
                if character == ",", depth == 0 {
                    items.append(current)
                    current = ""
                    continue
                }
            }
            current.append(character)
        }
        items.append(current)
        return items.compactMap { item in
            guard let equals = item.firstIndex(of: "=") else { return nil }
            let key = item[..<equals].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            return (key, item[item.index(after: equals)...].trimmingCharacters(in: .whitespaces))
        }
    }

    /// Een TOML-sleutel in delen: `target.'cfg(unix)'.dependencies` → target, cfg(unix), dependencies.
    static func keyParts(_ key: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        for character in key {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "." {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts
    }

    /// Openende min sluitende haken (`[`, `{`) buiten strings.
    private static func openBrackets(_ text: String) -> Int {
        var result = 0
        var quote: Character?
        for character in text {
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "[" || character == "{" {
                result += 1
            } else if character == "]" || character == "}" {
                result -= 1
            }
        }
        return result
    }

    /// Een regel zonder `# commentaar` buiten strings.
    private static func withoutComment(_ line: String) -> String {
        var quote: Character?
        for index in line.indices {
            let character = line[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#" {
                return String(line[..<index])
            }
        }
        return line
    }

    // MARK: - Workspaces

    /// Elke Cargo.toml van een repo (map → manifest) met de geërfde eisen ingevuld: een lid erft uit
    /// de dichtstbijzijnde map erboven (of zichzelf) met een `[workspace]`-tabel. Per map de
    /// declaraties.
    static func cargoDeclarations(_ manifests: [String: CargoManifest]) -> [String: [CargoDeclaration]] {
        manifests.reduce(into: [:]) { result, item in
            result[item.key] = item.value.resolved(root: cargoWorkspaceRoot(of: item.key, in: manifests))
        }
    }

    /// Het manifest van de workspace-root voor de map `folder`: die map zelf of de dichtstbijzijnde erboven.
    private static func cargoWorkspaceRoot(of folder: String, in manifests: [String: CargoManifest]) -> CargoManifest? {
        var parts = folder.split(separator: "/").map(String.init)
        while true {
            if let manifest = manifests[parts.joined(separator: "/")], manifest.isWorkspaceRoot { return manifest }
            if parts.isEmpty { return nil }
            parts.removeLast()
        }
    }

    /// Het manifest (namen, soorten, eisen) van één Cargo.toml met zijn declaraties; de sleutels
    /// van `[workspace.dependencies]` tellen als runtime-namen mee.
    static func cargoManifestNames(_ manifest: CargoManifest, declarations: [CargoDeclaration]) -> Manifest {
        var result = Manifest(ecosystem: "crates.io", names: [:])
        func add(_ name: String, _ kind: DependencyKind, _ range: String?) {
            if let range, result.ranges[name] == nil { result.ranges[name] = range }
            if let current = result.names[name], current.weight >= kind.weight { return }
            result.names[name] = kind
        }
        for declaration in manifest.workspace.values.sorted(by: { $0.key < $1.key }) {
            add(declaration.crate, .runtime, declaration.requirement)
        }
        for declaration in declarations { add(declaration.crate, declaration.kind, declaration.requirement) }
        return result
    }

    /// Bereik en soort van een directe crate uit de Cargo.toml's onder de map van zijn lockfile:
    /// elke eis die de geïnstalleerde versie toelaat telt (Cargo kiest één versie die ze allemaal
    /// haalt, dus samen met een komma: alle moeten gelden). `[workspace.dependencies]` telt via de
    /// leden die erven; alleen als geen lid de crate noemt, telt de eis uit de workspace zelf.
    static func cargoRequirement(
        of dependency: Dependency, lockfolder: String, declarations: [String: [CargoDeclaration]], manifests: [String: CargoManifest]
    ) -> (requested: String?, kind: DependencyKind?) {
        let wanted = UpdateContext.normalized(ecosystem: "crates.io", name: dependency.name)
        func inside(_ folder: String) -> Bool { lockfolder.isEmpty || folder == lockfolder || folder.hasPrefix(lockfolder + "/") }
        let matching = declarations.filter { inside($0.key) }.sorted { $0.key < $1.key }.flatMap(\.value)
            .filter { UpdateContext.normalized(ecosystem: "crates.io", name: $0.crate) == wanted }
        let workspace = manifests.filter { inside($0.key) }.sorted { $0.key < $1.key }.flatMap { $0.value.workspace.values }
            .filter { UpdateContext.normalized(ecosystem: "crates.io", name: $0.crate) == wanted }
        let kind = matching.map(\.kind).max { $0.weight < $1.weight }
        var ranges: [String] = []
        for range in (matching.isEmpty ? workspace : matching).compactMap(\.requirement) where !ranges.contains(range) { ranges.append(range) }
        let fitting = ranges.filter { CargoRequirement.parse($0)?.contains(dependency.version) == true }
        let requested = fitting.isEmpty ? (ranges.count == 1 ? ranges.first : nil) : fitting.joined(separator: ", ")
        return (requested, kind)
    }
}
