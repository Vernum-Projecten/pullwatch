import Foundation

extension DependencyDetector {
    // MARK: - NuGet

    /// packages.lock.json: per target framework (`net8.0`, ook `net8.0/win-x64`) elk package met
    /// `type` (`Direct`, `Transitive`, `CentralTransitive`, `Project`), `resolved` en zijn
    /// `dependencies`: de graaf. `Project` is een eigen project en geen install; wat het vraagt komt
    /// via dat project binnen. De map van het project is de workspace; dezelfde install in twee
    /// frameworks telt één keer. NuGet kent geen dev.
    static func nugetLock(_ content: String, path: String) -> LockfileRead {
        struct Entry: Decodable {
            let type: String?
            let requested: String?
            let resolved: String?
            let dependencies: [String: String]?
        }
        struct Lock: Decodable { let dependencies: [String: [String: Entry]] }
        var read = LockfileRead(ecosystem: "NuGet", source: path, dependencies: [])
        guard let lock = try? JSONDecoder().decode(Lock.self, from: Data(content.utf8)) else { return read }
        for framework in lock.dependencies.keys.sorted() {
            let packages = lock.dependencies[framework] ?? [:]
            // NuGet-namen zijn hoofdletterongevoelig; `dependencies` schrijft ze soms anders.
            var byKey: [String: (name: String, entry: Entry)] = [:]
            for (name, entry) in packages { byKey[name.lowercased()] = (name, entry) }
            let roots = byKey.filter { $0.value.entry.type == "Direct" || $0.value.entry.type == "Project" }
                .keys.sorted().map { (node: $0, kind: DependencyKind.runtime) }
            let reach = walk(
                roots: roots,
                children: { key in (byKey[key]?.entry.dependencies ?? [:]).keys.map { $0.lowercased() }.filter { byKey[$0] != nil }.sorted() },
                name: { byKey[$0]?.name ?? $0 }
            )
            /// Het bereik waarmee de ouder het package vraagt; NuGet schrijft de naam soms anders.
            func requested(by parent: String?, _ key: String) -> String? {
                guard let parent else { return nil }
                return byKey[parent]?.entry.dependencies?.first { $0.key.lowercased() == key }?.value
            }
            for key in byKey.keys.sorted() {
                guard let (name, entry) = byKey[key], entry.type != "Project",
                      let version = entry.resolved, isExactVersion(version) else { continue }
                let direct = entry.type == "Direct"
                read.dependencies.append(Dependency(
                    ecosystem: "NuGet", name: name, version: version, source: path, workspace: nil,
                    scope: direct ? .direct : .transitive, via: direct ? [] : reach[key]?.via ?? [],
                    requested: direct ? entry.requested : requested(by: reach[key]?.parent, key)
                ))
            }
        }
        read.dependencies = merged(read.dependencies)
        return read
    }

    // MARK: - RubyGems

    /// Gemfile.lock: de specs onder `GEM` (`    rack (2.2.8)`) zijn de installs, met hun
    /// ingesprongen dependencies (`      rack (>= 2)`) als graaf; specs onder `GIT` en `PATH` staan
    /// niet op rubygems.org maar tellen wel mee in de graaf. `DEPENDENCIES` is direct; de soort
    /// (`group :development`) komt uit de Gemfile. Een platform-achtervoegsel
    /// (`1.15.4-arm64-darwin`) valt weg voor OSV.
    static func gemfileLock(_ content: String, path: String) -> LockfileRead {
        var read = LockfileRead(ecosystem: "RubyGems", source: path, dependencies: [], kindsKnown: false)
        var graph: [String: [String]] = [:]
        var direct: [String: DependencyKind] = [:]
        var section = ""
        var current: String?
        var seen: Set<String> = []
        for raw in content.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if let first = line.first, first != " " {
                section = line.trimmingCharacters(in: .whitespaces)
                current = nil
                continue
            }
            let indent = line.prefix { $0 == " " }.count
            let text = line.trimmingCharacters(in: .whitespaces)
            switch section {
            case "GEM", "GIT", "PATH":
                if indent == 4, let m = text.wholeMatch(of: /([^\s(]+) \(([^)]+)\)/) {
                    let name = String(m.output.1)
                    current = name
                    if graph[name] == nil { graph[name] = [] }
                    guard section == "GEM" else { continue }
                    let version = String(m.output.2.split(separator: "-", maxSplits: 1).first ?? m.output.2)
                    guard isExactVersion(version), seen.insert("\(name)@\(version)").inserted else { continue }
                    read.dependencies.append(Dependency(ecosystem: "RubyGems", name: name, version: version, source: path,
                                                        workspace: nil, scope: .unknown))
                } else if indent == 6, let current, let m = text.firstMatch(of: /^([^\s(!]+)(?: \(([^)]+)\))?/) {
                    let child = String(m.output.1)
                    if !(graph[current] ?? []).contains(child) { graph[current, default: []].append(child) }
                    if let range = m.output.2 { read.requirements[current, default: [:]][child] = String(range) }
                }
            case "DEPENDENCIES":
                if indent == 2, let m = text.firstMatch(of: /^([^\s(!]+)(?: \(([^)]+)\))?/) {
                    direct[String(m.output.1)] = .runtime
                    if let range = m.output.2 { read.directRanges[String(m.output.1)] = String(range) }
                }
            default:
                continue
            }
        }
        read.graph = graph
        read.directNames = direct
        return read
    }

    /// Gemfile (en gems.rb): `gem "naam"` per regel, met de requirements erachter
    /// (`gem "rails", "~> 7.1", ">= 7.1.2"` → "~> 7.1, >= 7.1.2"). Binnen
    /// `group :development, :test do … end` of met `group: :test` is een gem dev, als alle groepen
    /// development of test zijn.
    static func gemfileNames(_ content: String) -> [(String, DependencyKind, String?)] {
        func kind(_ groups: Substring) -> DependencyKind {
            let names = groups.matches(of: /:(\w+)|"(\w+)"|'(\w+)'/).map { String($0.output.1 ?? $0.output.2 ?? $0.output.3 ?? "") }
            return !names.isEmpty && names.allSatisfy { $0 == "development" || $0 == "test" } ? .dev : .runtime
        }
        var names: [(String, DependencyKind, String?)] = []
        /// Per open blok: de soort van een `group`-blok, nil voor andere blokken (platforms, source).
        var blocks: [DependencyKind?] = []
        for raw in content.split(whereSeparator: \.isNewline) {
            let line = (raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
                .trimmingCharacters(in: .whitespaces)
            if line == "end" {
                _ = blocks.popLast()
                continue
            }
            let opens = line.wholeMatch(of: /.*\bdo(\s*\|[^|]*\|)?/) != nil
            if let m = line.wholeMatch(of: /group\b(.*)\bdo\b.*/) {
                blocks.append(kind(m.output.1))
                continue
            }
            if let m = line.firstMatch(of: /^gem\s*\(?\s*["']([^"']+)["'](.*)/) {
                var current = blocks.reversed().compactMap { $0 }.first ?? .runtime
                if let inline = m.output.2.firstMatch(of: /\bgroups?:\s*(\[[^\]]*\]|:\w+)/) { current = kind(inline.output.1) }
                // Strings direct na de naam, tot de eerste optie (`require: false`).
                let arguments = m.output.2.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " )")) }
                let requirements = arguments.dropFirst().prefix { $0.wholeMatch(of: /["'][^"']*["']/) != nil }
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                    .filter { $0.first.map { $0.isNumber || "~<>=!".contains($0) } ?? false }
                names.append((String(m.output.1), current, requirements.isEmpty ? nil : requirements.joined(separator: ", ")))
                if opens { blocks.append(nil) }
                continue
            }
            // Ook `if`, `unless`, `case` en `begin` sluiten met `end`.
            if opens || line.wholeMatch(of: /(if|unless|case|begin|while|def)\b.*/) != nil { blocks.append(nil) }
        }
        return names
    }
}
