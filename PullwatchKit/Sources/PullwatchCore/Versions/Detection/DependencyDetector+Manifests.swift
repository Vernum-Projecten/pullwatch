import Foundation

extension DependencyDetector {
    // MARK: - Manifesten zonder lockfile

    /// Alleen `pakket==versie`; extras (`pakket[x]==1`) en markers (`; python_version…`) worden genegeerd.
    /// De index van het bestand (`requirementsIndex`) geldt voor elk package erin.
    static func requirements(_ content: String, path: String) -> [Dependency] {
        let index = requirementsIndex(content)
        return content.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let spec = line.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            guard let m = spec.trimmingCharacters(in: .whitespaces).wholeMatch(of: /([A-Za-z0-9._-]+)(\[[^\]]*\])?\s*==\s*([^\s,]+)/) else {
                return nil
            }
            return Dependency(ecosystem: "PyPI", name: String(m.output.1), version: String(m.output.3), source: path, isDirect: true,
                              requested: "==\(m.output.3)", registry: index)
        }
    }

    /// `<PackageReference Include="X" Version="1.2.3" />` en `<PackageVersion …>`; attributen in elke volgorde.
    static func nugetPackages(_ content: String, path: String) -> [Dependency] {
        content.matches(of: /<Package(?:Reference|Version)\b([^>]*)>/).compactMap { match in
            let attributes = String(match.output.1)
            guard let include = attributes.firstMatch(of: /Include="([^"]+)"/)?.output.1,
                  let version = attributes.firstMatch(of: /Version="([^"$\[\]()*]+)"/)?.output.1 else { return nil }
            // Een kale versie is in NuGet een minimum.
            return Dependency(ecosystem: "NuGet", name: String(include), version: String(version), source: path, isDirect: true,
                              requested: String(version))
        }
    }

    // MARK: - Manifesten

    /// Namen die een manifest rechtstreeks vraagt, voor lockfiles die dat zelf niet zeggen
    /// (composer.lock, poetry.lock, package-lock v1).
    static func directNames(path: String, content: String) -> (ecosystem: String, names: Set<String>)? {
        manifest(path: path, content: content).map { ($0.ecosystem, Set($0.names.keys)) }
    }

    static func manifest(path: String, content: String) -> Manifest? {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        var names: [String: DependencyKind] = [:]
        var ranges: [String: String] = [:]
        func add(_ name: String, _ kind: DependencyKind, _ range: String? = nil) {
            if let range, ranges[name] == nil { ranges[name] = range }
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
                for (key, range) in field ?? [:] { add(key, kind, range) }
            }
            return Manifest(ecosystem: "npm", names: names, ranges: ranges)
        case "composer.json":
            struct ComposerJSON: Decodable {
                let require: [String: String]?
                let requireDev: [String: String]?
                enum CodingKeys: String, CodingKey { case require, requireDev = "require-dev" }
            }
            guard let manifest = try? JSONDecoder().decode(ComposerJSON.self, from: Data(content.utf8)) else { return nil }
            for (field, kind) in [(manifest.require, DependencyKind.runtime), (manifest.requireDev, .dev)] {
                for (key, range) in field ?? [:] where key != "php" && !key.hasPrefix("ext-") && key.contains("/") {
                    add(key.lowercased(), kind, range)
                }
            }
            return Manifest(ecosystem: "Packagist", names: names, ranges: ranges)
        case "pyproject.toml":
            for (key, kind, range) in pyprojectNames(content) { add(key, kind, range) }
            return Manifest(ecosystem: "PyPI", names: names, ranges: ranges)
        case "Cargo.toml":
            // Alleen dit bestand: een lid erft dan uit zijn eigen `[workspace.dependencies]` (zie `installs`).
            let cargo = cargoManifest(content)
            return cargoManifestNames(cargo, declarations: cargo.resolved(root: nil))
        case "Gemfile", "gems.rb":
            for (key, kind, range) in gemfileNames(content) { add(key, kind, range) }
            return Manifest(ecosystem: "RubyGems", names: names, ranges: ranges)
        case "Package.swift":
            // Alleen bereiken: of een pin direct is, blijft onbekend (zie `direct`).
            return Manifest(ecosystem: "SwiftURL", names: [:], ranges: swiftRequirements(content))
        default:
            return nil
        }
    }

    /// `[project] dependencies = [ "pakket>=1", … ]` (runtime), `[project.optional-dependencies]`
    /// (optioneel), `[dependency-groups]` en `[tool.uv] dev-dependencies` (dev), en de sleutels van
    /// `[tool.poetry.dependencies]` (zonder python) en `[tool.poetry.group.<g>.dependencies]` (dev,
    /// behalve main).
    private static func pyprojectNames(_ content: String) -> [(String, DependencyKind, String?)] {
        var names: [(String, DependencyKind, String?)] = []
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
                for match in line.matches(of: /"([^"]*)"/) where !line.contains("include-group") {
                    if let requirement = pep508(String(match.output.1)) {
                        names.append((normalizedPyPIName(requirement.name), kind, requirement.specifier))
                    }
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
            if let poetryKind, let m = line.firstMatch(of: /^([A-Za-z0-9][A-Za-z0-9._-]*)\s*=\s*(.*)/) {
                let name = String(m.output.1)
                // `requests = "^2.28"` of `requests = { version = "^2.28", optional = true }`.
                let value = String(m.output.2).trimmingCharacters(in: .whitespaces)
                let range = TomlPackage.string(value) ?? value.firstMatch(of: /\bversion\s*=\s*"([^"]+)"/).map { String($0.output.1) }
                if name != "python" { names.append((normalizedPyPIName(name), poetryKind, range)) }
            }
        }
        return names
    }

    /// PEP 508: "requests[socks] >= 2.28, < 3 ; python_version < '3.8'" → ("requests", ">= 2.28, < 3").
    /// Zonder specifier (of met een URL na `@`) nil als bereik; geen naam vooraan: nil.
    static func pep508(_ requirement: String) -> (name: String, specifier: String?)? {
        let withoutMarker = requirement.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        guard let m = withoutMarker.wholeMatch(of: /\s*([A-Za-z0-9][A-Za-z0-9._-]*)\s*(?:\[[^\]]*\])?\s*(.*)/) else { return nil }
        var specifier = String(m.output.2).trimmingCharacters(in: .whitespaces)
        if specifier.hasPrefix("("), specifier.hasSuffix(")") { specifier = String(specifier.dropFirst().dropLast()) }
        if specifier.hasPrefix("@") || specifier.isEmpty { return (String(m.output.1), nil) }
        return (String(m.output.1), specifier)
    }

    /// `.package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0")` in Package.swift →
    /// "github.com/apple/swift-nio": `from: "2.0.0"`. Ook `.upToNextMajor(from:)`,
    /// `.upToNextMinor(from:)`, `exact:`, `.exact(_:)` en `"a"..<"b"`; `branch:`, `revision:` en
    /// `path:` geven niets.
    static func swiftRequirements(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        var rest = Substring(content)
        while let start = rest.range(of: ".package(") {
            // Tot het haakje dat dit `.package(` sluit.
            var depth = 1
            var index = start.upperBound
            while index < rest.endIndex, depth > 0 {
                if rest[index] == "(" { depth += 1 }
                if rest[index] == ")" { depth -= 1 }
                index = rest.index(after: index)
            }
            let inner = rest[start.upperBound..<index]
            rest = rest[index...]
            guard let url = inner.firstMatch(of: /url:\s*"([^"]+)"/)?.output.1 else { continue }
            let patterns: [Regex<Substring>] = [
                /\.(?:upToNextMajor|upToNextMinor|exact)\s*\(\s*(?:from\s*:\s*)?"[^"]+"\s*\)/,
                /"[^"]+"\s*\.\.[.<]\s*"[^"]+"/,
                /\b(?:from|exact)\s*:\s*"[^"]+"/,
            ]
            if let requirement = patterns.lazy.compactMap({ inner.firstMatch(of: $0) }).first {
                result[swiftPackageName(String(url))] = String(requirement.output)
            }
        }
        return result
    }
}
