import Foundation

/// Wat de check nog moet ophalen om een update te beoordelen.
struct UpdateNeeds: Sendable {
    /// `PackageUse.key`'s zonder metadata.
    var packages: Set<String> = []
    /// Versies waarvan de dependencies (of de go.mod) nog ontbreken.
    var details: Set<DetailRequest> = []
    /// Go-modules waarvan alle versies nodig zijn (`@v/list`).
    var versionLists: Set<String> = []

    var isEmpty: Bool { packages.isEmpty && details.isEmpty && versionLists.isEmpty }

    /// Neemt uit `other` alleen wat voor `version` nodig is, plus ontbrekende packages.
    mutating func formUnion(_ other: UpdateNeeds, onlyFor version: String) {
        packages.formUnion(other.packages)
        details.formUnion(other.details.filter { $0.version == version })
    }
}

struct DetailRequest: Hashable, Sendable {
    let ecosystem: String
    let name: String
    let version: String

    var key: String { "\(ecosystem):\(name)" }
}

/// De metadata van een rapport, één keer gelezen voor alle repo's: per package de versies die
/// een update kunnen zijn, oplopend.
public struct RegistryIndex: Sendable {
    struct Candidate: Sendable {
        let text: String
        let version: Version
        let metadata: VersionMetadata
    }

    /// Per `PackageUse.key`.
    let metadata: [String: PackageMetadata]
    let candidates: [String: [Candidate]]

    public static let empty = RegistryIndex([:])

    public init(_ metadata: [String: PackageMetadata]) {
        self.metadata = metadata
        self.candidates = metadata.mapValues { package in
            package.candidates.map { Candidate(text: $0.text, version: $0.version, metadata: $0.metadata) }
        }
    }

    /// De metadata van `version` van `key`, ook als het register hem anders schrijft.
    func metadata(key: String, version: Version) -> (text: String, metadata: VersionMetadata)? {
        guard let package = metadata[key] else { return nil }
        if let exact = package.versions[version.text] { return (version.text, exact) }
        if let candidate = candidates[key]?.first(where: { $0.version == version }) { return (candidate.text, candidate.metadata) }
        return package.versions.first { Version($0.key) == version }.map { ($0.key, $0.value) }
    }
}

/// Alles wat de blokkades van één repo nodig hebben: de metadata uit de registers, de runtimes
/// die de repo gebruikt en wat er per workspace geïnstalleerd is.
public struct UpdateContext: Sendable {
    let index: RegistryIndex
    /// Runtime (endoflife.date-product) → de oudste versie in de repo.
    public let runtimes: [String: String]
    /// "ecosysteem|workspace" → genormaliseerde naam → (naam, versies).
    let installed: [String: [String: (name: String, versions: [String])]]
    /// npm: "workspace" → genormaliseerde naam → wie hem als peer vraagt (package, versie, bereik).
    let peerRequirements: [String: [String: [(package: String, version: String, requirement: String)]]]

    public static let empty = UpdateContext(index: .empty, runtimes: [:], installed: [:])

    /// Per `PackageUse.key`.
    public var metadata: [String: PackageMetadata] { index.metadata }

    init(index: RegistryIndex, runtimes: [String: String], installed: [String: [String: (name: String, versions: [String])]]) {
        self.index = index
        self.runtimes = runtimes
        self.installed = installed
        var peers: [String: [String: [(package: String, version: String, requirement: String)]]] = [:]
        for (place, packages) in installed where place.hasPrefix("npm|") {
            let workspace = String(place.dropFirst(4))
            for package in packages.values {
                for version in package.versions {
                    guard let parsed = Version(version),
                          let found = index.metadata(key: "npm:\(package.name)", version: parsed) else { continue }
                    for (peer, requirement) in found.metadata.peerDependencies {
                        peers[workspace, default: [:]][peer, default: []].append((package.name, version, requirement))
                    }
                }
            }
        }
        self.peerRequirements = peers.mapValues { $0.mapValues { $0.sorted { ($0.package, $0.version) < ($1.package, $1.version) } } }
    }

    /// De context van `repo`: runtimes uit zijn onderdelen, installs uit al zijn packages.
    public init(repo: RepoVersions, metadata: [String: PackageMetadata]) {
        self.init(repo: repo, index: RegistryIndex(metadata))
    }

    public init(repo: RepoVersions, index: RegistryIndex) {
        var runtimes: [String: String] = [:]
        for component in repo.components where Self.runtimeProducts.contains(component.product) {
            if let current = runtimes[component.product], !VersionChecker.isOlder(component.version, than: current) { continue }
            runtimes[component.product] = component.version
        }
        var installed: [String: [String: (name: String, versions: [String])]] = [:]
        for package in repo.packages + repo.otherPackages {
            let name = Self.normalized(ecosystem: package.ecosystem, name: package.name)
            for install in package.installs {
                let place = "\(package.ecosystem)|\(install.workspace)"
                var entry = installed[place]?[name] ?? (package.name, [])
                if !entry.versions.contains(install.version) { entry.versions.append(install.version) }
                installed[place, default: [:]][name] = entry
            }
        }
        self.init(index: index, runtimes: runtimes, installed: installed)
    }

    static let runtimeProducts: Set<String> = ["nodejs", "php", "python", "rust", "dotnet", "ruby", "go"]

    /// Namen zoals het register ze vergelijkt: PyPI en crates.io maken geen verschil tussen "-",
    /// "_" en "."; Packagist, PyPI en NuGet niet tussen hoofd- en kleine letters.
    static func normalized(ecosystem: String, name: String) -> String {
        switch ecosystem {
        case "PyPI", "crates.io": name.lowercased().replacing(/[-_.]+/, with: "-")
        case "Packagist", "NuGet": name.lowercased()
        default: name
        }
    }

    func installedVersions(ecosystem: String, workspace: String, name: String) -> [String] {
        installed["\(ecosystem)|\(workspace)"]?[Self.normalized(ecosystem: ecosystem, name: name)]?.versions ?? []
    }

    // MARK: - Blokkades

    /// Uitkomst van één versie tegen elke eis.
    enum Check: Equatable {
        case passes
        case blocked(UpdateBlocker)
        /// Er ontbreekt nog metadata om het te zeggen.
        case unknown
    }

    /// Wat `target` van `name` voor deze install tegenhoudt: eerst de ouder (zijn bereik), dan een
    /// package dat dit package als peer vraagt, dan de peers en de runtime van `target` zelf.
    /// - Parameter findMinimum: zoekt bij een ouder de laagste versie die `target` toelaat.
    func check(
        ecosystem: String, name: String, install: PackageInstall, target: Version, findMinimum: Bool, needs: inout UpdateNeeds
    ) -> Check {
        if install.scope == .transitive, let parent = install.via.last, let requested = install.requested,
           let range = VersionRange.parse(ecosystem: ecosystem, name: name, requested: requested), !range.contains(target) {
            let minimum = findMinimum
                ? lowestParent(ecosystem: ecosystem, parent: parent, workspace: install.workspace, child: name, target: target, needs: &needs)
                : nil
            return .blocked(.package(parent: parent, parentRange: requested, minimumParentVersion: minimum))
        }
        if let blocker = peerRequirement(ecosystem: ecosystem, name: name, workspace: install.workspace, target: target, findMinimum: findMinimum) {
            return .blocked(blocker)
        }
        let key = "\(ecosystem):\(name)"
        guard index.metadata[key] != nil else {
            needs.packages.insert(key)
            return .unknown
        }
        guard let found = index.metadata(key: key, version: target) else { return .unknown }
        let metadata = found.metadata
        if ecosystem == "Go", metadata.dependencies == nil {
            needs.details.insert(DetailRequest(ecosystem: ecosystem, name: name, version: found.text))
            return .unknown
        }
        for (peer, requirement) in metadata.peerDependencies.sorted(by: { $0.key < $1.key }) {
            guard let range = VersionRange.parse(ecosystem: ecosystem, name: peer, requested: requirement) else { continue }
            let versions = installedVersions(ecosystem: ecosystem, workspace: install.workspace, name: peer)
            if let outside = versions.first(where: { !range.contains($0) }) {
                return .blocked(.peer(name: peer, needs: requirement, installed: outside))
            }
        }
        for (runtime, requirement) in metadata.runtimes.sorted(by: { $0.key < $1.key }) {
            guard let installed = runtimes[runtime],
                  RuntimeRequirement.isSatisfied(runtime: runtime, requirement: requirement, installed: installed) == false else { continue }
            return .blocked(.runtime(runtime: runtime, needs: requirement, installed: installed))
        }
        return .passes
    }

    /// Een ander package in dezelfde workspace dat `name` als peer vraagt met een bereik zonder
    /// `target` (npm: `react-dom` 18 houdt `react` 19 tegen).
    private func peerRequirement(ecosystem: String, name: String, workspace: String, target: Version, findMinimum: Bool) -> UpdateBlocker? {
        guard ecosystem == "npm", let requirements = peerRequirements[workspace]?[name] else { return nil }
        for (package, version, requirement) in requirements where package != name {
            guard let range = VersionRange.parse(ecosystem: ecosystem, name: name, requested: requirement), !range.contains(target) else { continue }
            var minimum: String?
            if findMinimum {
                minimum = lowest(after: version, of: "npm:\(package)", admits: { metadata -> Bool? in
                    // Een latere versie zonder deze peer houdt niets meer tegen.
                    guard let requirement = metadata.peerDependencies[name] else { return true }
                    return VersionRange.parse(ecosystem: ecosystem, name: name, requested: requirement)?.contains(target) ?? true
                }, request: { _ in })
            }
            return .package(parent: package, parentRange: requirement, minimumParentVersion: minimum)
        }
        return nil
    }

    /// De laagste versie van `parent` na de geïnstalleerde waarvan het bereik voor `child` `target` toelaat.
    private func lowestParent(
        ecosystem: String, parent: String, workspace: String, child: String, target: Version, needs: inout UpdateNeeds
    ) -> String? {
        let key = "\(ecosystem):\(parent)"
        guard index.metadata[key] != nil else {
            needs.packages.insert(key)
            return nil
        }
        let installed = installedVersions(ecosystem: ecosystem, workspace: workspace, name: parent)
            .min { VersionChecker.isOlder($0, than: $1) }
        let wanted = Self.normalized(ecosystem: ecosystem, name: child)
        var requests: [String] = []
        let found = lowest(after: installed, of: key, admits: { metadata -> Bool? in
            guard let dependencies = metadata.dependencies else { return nil }
            let all = dependencies.merging(metadata.peerDependencies) { first, _ in first }
            // Een versie die het package niet meer vraagt, houdt het ook niet tegen.
            guard let requirement = all.first(where: { Self.normalized(ecosystem: ecosystem, name: $0.key) == wanted })?.value else { return true }
            if let range = VersionRange.parse(ecosystem: ecosystem, name: child, requested: requirement) { return range.contains(target) }
            let bare = requirement.trimmingCharacters(in: .whitespaces)
            return bare.isEmpty || bare == "*"
        }, request: { requests.append($0) })
        for version in requests { needs.details.insert(DetailRequest(ecosystem: ecosystem, name: parent, version: version)) }
        return found
    }

    /// De laagste versie van `key` na `installed` waarvoor `admits` ja zegt. Zonder ontbrekende
    /// gegevens precies (van laag naar hoog); anders binair zoeken, ervan uitgaand dat een nieuwere
    /// versie niet strenger wordt, met `request` voor de versie die het eerst nodig is. Zolang die
    /// ontbreekt, is het antwoord de laagste bekende die past.
    func lowest(after installed: String?, of key: String, admits: (VersionMetadata) -> Bool?, request: (String) -> Void) -> String? {
        let floor = installed.flatMap { Version($0) }
        let items = (index.candidates[key] ?? []).filter { candidate in floor.map { candidate.version > $0 } ?? true }
        let answers = items.map { admits($0.metadata) }
        if !answers.contains(nil) {
            return items.indices.first { answers[$0] == true }.map { items[$0].text }
        }
        guard let last = items.indices.last else { return nil }
        guard let top = answers[last] else {
            request(items[last].text)
            return nil
        }
        guard top else { return nil }
        var low = 0, high = last
        while low < high {
            let middle = (low + high) / 2
            guard let answer = answers[middle] else {
                request(items[middle].text)
                break
            }
            if answer { high = middle } else { low = middle + 1 }
        }
        return items[high].text
    }

    /// De hoogste versie van `name` na `install` die elke eis haalt; de geïnstalleerde versie als
    /// geen nieuwere dat doet, nil als het niet te zeggen is. Zonder ontbrekende gegevens precies;
    /// anders binair zoeken, ervan uitgaand dat een oudere versie niet strenger is.
    func newestUsable(ecosystem: String, name: String, install: PackageInstall, needs: inout UpdateNeeds) -> String? {
        let key = "\(ecosystem):\(name)"
        guard let package = index.metadata[key], let current = Version(install.version) else { return nil }
        let items = (index.candidates[key] ?? []).filter { $0.version > current }
        var probe = UpdateNeeds()
        let answers: [Check] = items.map {
            check(ecosystem: ecosystem, name: name, install: install, target: $0.version, findMinimum: false, needs: &probe)
        }
        if package.isComplete, !answers.contains(.unknown) {
            return items.indices.last { answers[$0] == .passes }.map { items[$0].text } ?? install.version
        }
        guard let last = items.indices.last else { return package.isComplete ? install.version : nil }
        if answers[last] == .passes { return items[last].text }
        if answers[last] == .unknown {
            needs.formUnion(probe, onlyFor: items[last].text)
            return nil
        }
        // Go: de nieuwste haalt het niet; eerst alle versies (`@v/list`).
        guard package.isComplete else {
            needs.versionLists.insert(key)
            return nil
        }
        var low = -1, high = last
        while high - low > 1 {
            let middle = (low + high) / 2
            switch answers[middle] {
            case .passes: low = middle
            case .blocked: high = middle
            case .unknown:
                needs.formUnion(probe, onlyFor: items[middle].text)
                return low >= 0 ? items[low].text : nil
            }
        }
        return low >= 0 ? items[low].text : install.version
    }
}
