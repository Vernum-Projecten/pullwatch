import Foundation

// MARK: - Lezen

extension RegistryMetadata {
    /// Nieuwste versie en metadata per versie uit het hoofddocument.
    static func decode(ecosystem: String, name: String, data: Data) throws -> (latest: String?, versions: [String: VersionMetadata]) {
        switch ecosystem {
        case "npm": return try decodeNpm(data)
        case "Packagist": return try decodePackagist(data, name: name)
        case "crates.io": return try decodeCrates(data)
        case "NuGet": return try decodeNuGet(data)
        case "RubyGems": return try decodeRubyGems(data)
        case "PyPI": return try decodePyPI(data)
        case "Go":
            guard let latest = try PackageRegistry.decodeLatest(ecosystem: "Go", name: name, data: data) else { return (nil, [:]) }
            return (latest, [latest: VersionMetadata()])
        default: return (nil, [:])
        }
    }

    /// Dependencies (en voor Go en PyPI de runtime) uit het document van één versie.
    static func decodeDetail(ecosystem: String, data: Data) throws -> VersionMetadata {
        switch ecosystem {
        case "crates.io":
            struct Response: Decodable {
                struct Dependency: Decodable {
                    let crate_id: String
                    let req: String
                    let kind: String?
                }
                let dependencies: [Dependency]
            }
            let dependencies = try JSONDecoding.decode(Response.self, from: data).dependencies.filter { ($0.kind ?? "normal") == "normal" }
            return VersionMetadata(dependencies: Dictionary(dependencies.map { ($0.crate_id, $0.req) }, uniquingKeysWith: { first, _ in first }))
        case "RubyGems":
            struct Response: Decodable {
                struct Dependencies: Decodable {
                    struct Gem: Decodable {
                        let name: String
                        let requirements: String
                    }
                    let runtime: [Gem]?
                }
                let dependencies: Dependencies?
                let ruby_version: String?
                let rubygems_version: String?
            }
            let response = try JSONDecoding.decode(Response.self, from: data)
            return VersionMetadata(
                dependencies: Dictionary((response.dependencies?.runtime ?? []).map { ($0.name, $0.requirements) }, uniquingKeysWith: { first, _ in first }),
                runtimes: rubyRuntimes(ruby: response.ruby_version, rubygems: response.rubygems_version)
            )
        case "PyPI":
            struct Response: Decodable {
                struct Info: Decodable {
                    let requires_python: String?
                    let requires_dist: [String]?
                }
                let info: Info
            }
            let info = try JSONDecoding.decode(Response.self, from: data).info
            var runtimes: [String: String] = [:]
            if let python = info.requires_python?.trimmingCharacters(in: .whitespaces), !python.isEmpty { runtimes["python"] = python }
            return VersionMetadata(dependencies: requiresDist(info.requires_dist ?? []), runtimes: runtimes)
        case "Go":
            return goMod(String(decoding: data, as: UTF8.self))
        default:
            return VersionMetadata(dependencies: [:])
        }
    }

    /// Een map die bij een ander type (oude packages hebben `engines` als lijst) leeg blijft.
    struct LenientMap: Decodable {
        let values: [String: String]

        init(from decoder: any Decoder) throws {
            values = (try? decoder.singleValueContainer().decode([String: String].self)) ?? [:]
        }
    }

    /// Tekst, of iets anders dat als "ja" telt (`deprecated` is soms `true`).
    struct LenientFlag: Decodable {
        let isSet: Bool

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                isSet = !text.isEmpty
            } else {
                isSet = (try? container.decode(Bool.self)) ?? false
            }
        }
    }

    private static func decodeNpm(_ data: Data) throws -> (latest: String?, versions: [String: VersionMetadata]) {
        struct Packument: Decodable {
            struct Entry: Decodable {
                struct Meta: Decodable { let optional: Bool? }
                let dependencies: LenientMap?
                let optionalDependencies: LenientMap?
                let peerDependencies: LenientMap?
                let peerDependenciesMeta: [String: Meta]?
                let engines: LenientMap?
                let deprecated: LenientFlag?
            }
            let distTags: [String: String]?
            let versions: [String: Entry]?

            enum CodingKeys: String, CodingKey {
                case distTags = "dist-tags"
                case versions
            }
        }
        let packument = try JSONDecoding.decode(Packument.self, from: data)
        var versions: [String: VersionMetadata] = [:]
        for (version, entry) in packument.versions ?? [:] {
            var runtimes: [String: String] = [:]
            if let node = entry.engines?.values["node"], !node.trimmingCharacters(in: .whitespaces).isEmpty { runtimes["nodejs"] = node }
            versions[version] = VersionMetadata(
                dependencies: (entry.optionalDependencies?.values ?? [:]).merging(entry.dependencies?.values ?? [:]) { _, new in new },
                peerDependencies: entry.peerDependencies?.values ?? [:],
                optionalPeers: (entry.peerDependenciesMeta ?? [:]).filter { $0.value.optional == true }.keys.sorted(),
                runtimes: runtimes,
                isWithdrawn: entry.deprecated?.isSet ?? false
            )
        }
        return (packument.distTags?["latest"], versions)
    }

    /// Composer 2 verkleint `p2`: elke versie (nieuwste eerst) noemt alleen wat verschilt van de
    /// vorige; `"__unset"` haalt een veld weg (composer/metadata-minifier).
    private static func decodePackagist(_ data: Data, name: String) throws -> (latest: String?, versions: [String: VersionMetadata]) {
        struct Response: Decodable {
            let packages: [String: [Entry]]
            let minified: String?
        }
        struct Entry: Decodable {
            enum Field: Equatable {
                case inherited, unset, value([String: String])
            }
            let version: String
            let require: Field

            enum CodingKeys: String, CodingKey { case version, require }

            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                version = try c.decode(String.self, forKey: .version)
                if !c.contains(.require) {
                    require = .inherited
                } else if let text = try? c.decode(String.self, forKey: .require) {
                    require = text == "__unset" ? .unset : .value([:])
                } else {
                    // Een lege `require` is in JSON soms een lege lijst.
                    require = .value((try? c.decode([String: String].self, forKey: .require)) ?? [:])
                }
            }
        }
        let response = try JSONDecoding.decode(Response.self, from: data)
        let entries = response.packages[name.lowercased()] ?? []
        let minified = response.minified == "composer/2.0"
        var versions: [String: VersionMetadata] = [:]
        var current: [String: String] = [:]
        for entry in entries {
            switch entry.require {
            case .value(let require): current = require
            case .unset: current = [:]
            case .inherited: if !minified { current = [:] }
            }
            let version = entry.version.droppingVersionPrefix
            guard !version.hasPrefix("dev-") else { continue }
            var runtimes: [String: String] = [:]
            if let php = current["php"] { runtimes["php"] = php }
            let platform = { (package: String) in
                package == "php" || package.hasPrefix("php-") || package.hasPrefix("ext-") || package.hasPrefix("lib-")
                    || package.hasPrefix("composer-")
            }
            versions[version] = VersionMetadata(dependencies: current.filter { !platform($0.key) }, runtimes: runtimes)
        }
        return (PackageRegistry.highestStable(Array(versions.keys)), versions)
    }

    private static func decodeCrates(_ data: Data) throws -> (latest: String?, versions: [String: VersionMetadata]) {
        struct Response: Decodable {
            struct Crate: Decodable { let max_stable_version: String? }
            struct Entry: Decodable {
                let num: String
                let rust_version: String?
                let yanked: Bool?
            }
            let crate: Crate
            let versions: [Entry]?
        }
        let response = try JSONDecoding.decode(Response.self, from: data)
        var versions: [String: VersionMetadata] = [:]
        for entry in response.versions ?? [] {
            var runtimes: [String: String] = [:]
            if let rust = entry.rust_version, !rust.isEmpty { runtimes["rust"] = ">= \(rust)" }
            versions[entry.num] = VersionMetadata(runtimes: runtimes, isWithdrawn: entry.yanked ?? false)
        }
        return (response.crate.max_stable_version, versions)
    }

    private struct NuGetPage: Decodable {
        struct Leaf: Decodable {
            struct Entry: Decodable {
                struct Group: Decodable {
                    struct Dependency: Decodable {
                        let id: String
                        let range: String?
                    }
                    let targetFramework: String?
                    let dependencies: [Dependency]?
                }
                let version: String
                let listed: Bool?
                let dependencyGroups: [Group]?
            }
            let catalogEntry: Entry
        }
        let id: String
        let upper: String?
        let items: [Leaf]?

        enum CodingKeys: String, CodingKey {
            case id = "@id"
            case upper, items
        }
    }

    private struct NuGetIndex: Decodable {
        let items: [NuGetPage]
    }

    private static func decodeNuGet(_ data: Data) throws -> (latest: String?, versions: [String: VersionMetadata]) {
        let index = try JSONDecoding.decode(NuGetIndex.self, from: data)
        let versions = nugetVersions(index.items.flatMap { $0.items ?? [] })
        // Pagina's die niet in de index staan, komen er in `fetch` bij; de nieuwste staat dan in de laatste.
        return (PackageRegistry.highestStable(versions.filter { !$0.value.isWithdrawn }.map(\.key)), versions)
    }

    /// De pagina's zonder `items` waarvan de hoogste versie op of boven `floor` ligt: de
    /// nieuwste eerst, hoogstens `nugetPageLimit`.
    static func nugetPages(data: Data, floor: String?, http: any HTTPClient, now: Date) async throws -> [String: VersionMetadata] {
        let index = try JSONDecoding.decode(NuGetIndex.self, from: data)
        let lowest = floor.flatMap { Version($0) }
        let wanted = index.items.reversed().filter { page in
            guard page.items == nil else { return false }
            guard let lowest, let upper = page.upper.flatMap({ Version($0) }) else { return true }
            return upper >= lowest
        }.prefix(nugetPageLimit)
        var versions: [String: VersionMetadata] = [:]
        for page in wanted {
            guard let url = URL(string: page.id) else { continue }
            let page = try JSONDecoding.decode(NuGetPage.self, from: try await get(url, ecosystem: "NuGet", http: http, now: now))
            versions.merge(nugetVersions(page.items ?? [])) { first, _ in first }
        }
        return versions
    }

    static let nugetPageLimit = 4

    private static func nugetVersions(_ leaves: [NuGetPage.Leaf]) -> [String: VersionMetadata] {
        var versions: [String: VersionMetadata] = [:]
        for leaf in leaves {
            let entry = leaf.catalogEntry
            let groups = entry.dependencyGroups ?? []
            var dependencies: [String: String] = [:]
            for group in groups {
                for dependency in group.dependencies ?? [] where dependencies[dependency.id] == nil {
                    dependencies[dependency.id] = dependency.range ?? ""
                }
            }
            var runtimes: [String: String] = [:]
            if let minimum = dotnetMinimum(groups.map { $0.targetFramework ?? "" }) { runtimes["dotnet"] = ">= \(minimum)" }
            let version = entry.version.split(separator: "+").first.map(String.init) ?? entry.version
            versions[version] = VersionMetadata(dependencies: dependencies, runtimes: runtimes, isWithdrawn: entry.listed == false)
        }
        return versions
    }

    /// De laagste moderne .NET (`net8.0`, `.NETCoreApp3.1`) waarvoor een package gebouwd is; nil als
    /// het ook voor .NET Standard of zonder framework bestaat (dan past het overal), of alleen
    /// voor .NET Framework (dat zegt niets over een .NET-project).
    static func dotnetMinimum(_ frameworks: [String]) -> String? {
        guard !frameworks.isEmpty else { return nil }
        let lowered = frameworks.map { $0.lowercased() }
        if lowered.contains(where: { $0.isEmpty || $0.hasPrefix(".netstandard") || $0.hasPrefix("netstandard") || $0 == "any" }) { return nil }
        let modern = lowered.compactMap { framework -> String? in
            if let m = framework.wholeMatch(of: /net(\d+\.\d+)(-.*)?/), (Int(m.output.1.split(separator: ".")[0]) ?? 0) >= 5 {
                return String(m.output.1)
            }
            if let m = framework.wholeMatch(of: /\.netcoreapp(\d+\.\d+)/) { return String(m.output.1) }
            return nil
        }
        return modern.min { VersionChecker.isOlder($0, than: $1) }
    }

    private static func decodeRubyGems(_ data: Data) throws -> (latest: String?, versions: [String: VersionMetadata]) {
        struct Entry: Decodable {
            let number: String
            let platform: String?
            let prerelease: Bool?
            let ruby_version: String?
            let rubygems_version: String?
        }
        let entries = try JSONDecoding.decode([Entry].self, from: data)
        var versions: [String: VersionMetadata] = [:]
        // Per versie het gewone platform ("ruby"); anders het eerste.
        for entry in entries where versions[entry.number] == nil || entry.platform == "ruby" {
            versions[entry.number] = VersionMetadata(runtimes: rubyRuntimes(ruby: entry.ruby_version, rubygems: entry.rubygems_version))
        }
        let stable = entries.filter { $0.prerelease != true && !$0.number.contains(where: \.isLetter) }.map(\.number)
        return (stable.max { VersionChecker.isOlder($0, than: $1) }, versions)
    }

    /// `">= 0"` zegt niets en telt niet.
    private static func rubyRuntimes(ruby: String?, rubygems: String?) -> [String: String] {
        var runtimes: [String: String] = [:]
        for (runtime, requirement) in [("ruby", ruby), ("rubygems", rubygems)] {
            guard let requirement = requirement?.trimmingCharacters(in: .whitespaces), !requirement.isEmpty,
                  requirement != ">= 0" else { continue }
            runtimes[runtime] = requirement
        }
        return runtimes
    }

    private static func decodePyPI(_ data: Data) throws -> (latest: String?, versions: [String: VersionMetadata]) {
        struct Response: Decodable {
            struct Info: Decodable { let version: String }
            struct File: Decodable {
                let requires_python: String?
                let yanked: Bool?
            }
            let info: Info
            let releases: [String: [File]]?
        }
        let response = try JSONDecoding.decode(Response.self, from: data)
        var versions: [String: VersionMetadata] = [:]
        for (version, files) in response.releases ?? [:] {
            var runtimes: [String: String] = [:]
            if let python = files.compactMap(\.requires_python).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                runtimes["python"] = python
            }
            // Een release zonder bestanden of met alleen ingetrokken bestanden is niet te installeren.
            versions[version] = VersionMetadata(runtimes: runtimes, isWithdrawn: files.isEmpty || files.allSatisfy { $0.yanked == true })
        }
        return (response.info.version, versions)
    }

    /// `requires_dist` (PEP 508): naam, eventueel extras en een specifier, en na ";" een marker.
    /// Wat alleen voor een extra geldt, telt niet.
    static func requiresDist(_ lines: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for line in lines {
            let parts = line.split(separator: ";", maxSplits: 1)
            if parts.count > 1, parts[1].contains("extra") { continue }
            let requirement = parts.first.map(String.init) ?? ""
            guard let match = requirement.firstMatch(of: /^\s*([A-Za-z0-9][A-Za-z0-9._-]*)\s*(\[[^\]]*\])?\s*(.*)$/) else { continue }
            let specifier = String(match.output.3).trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
            if result[String(match.output.1)] == nil { result[String(match.output.1)] = specifier }
        }
        return result
    }

    /// De `go`-regel en de `require`s van een go.mod.
    static func goMod(_ content: String) -> VersionMetadata {
        var runtimes: [String: String] = [:]
        var dependencies: [String: String] = [:]
        var inBlock = false
        for raw in content.split(whereSeparator: \.isNewline) {
            let line = raw.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first.map {
                $0.trimmingCharacters(in: .whitespaces)
            } ?? ""
            if line.hasPrefix("go "), let version = line.split(separator: " ").last {
                runtimes["go"] = ">= \(version)"
            } else if line == "require (" {
                inBlock = true
            } else if inBlock && line == ")" {
                inBlock = false
            } else if inBlock || line.hasPrefix("require ") {
                let fields = line.split(separator: " ").filter { $0 != "require" }
                if fields.count >= 2 {
                    let version = fields[1].droppingVersionPrefix
                    dependencies[String(fields[0])] = version
                }
            }
        }
        return VersionMetadata(dependencies: dependencies, runtimes: runtimes)
    }
}
