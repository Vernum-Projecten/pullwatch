import Foundation

// MARK: - Metadata van de registers

extension VersionChecker {
    /// Per `PackageUse.key` de oudste geïnstalleerde versie en alle geïnstalleerde versies.
    static func floors(_ dependencies: [Dependency]) -> [String: (floor: String, keep: Set<String>)] {
        var result: [String: (floor: String, keep: Set<String>)] = [:]
        for dependency in dependencies {
            let key = "\(dependency.ecosystem):\(dependency.name)"
            if var entry = result[key] {
                if isOlder(dependency.version, than: entry.floor) { entry.floor = dependency.version }
                entry.keep.insert(dependency.version)
                result[key] = entry
            } else {
                result[key] = (dependency.version, [dependency.version])
            }
        }
        return result
    }

    /// Haalt het document van elk package in `keys` ("ecosysteem:naam"), hooguit acht tegelijk;
    /// packages van een register dat uit staat worden overgeslagen.
    func fetchMetadata(
        _ keys: [String], floors: [String: (floor: String, keep: Set<String>)], date: Date
    ) async -> [String: PackageMetadata] {
        var result: [String: PackageMetadata] = [:]
        let cache = metadataCache
        await withTaskGroup(of: (String, PackageMetadata?).self) { group in
            var pending = keys.filter(isRegistryEnabled(key:)).sorted().makeIterator()
            func addNext() {
                guard let key = pending.next(), case let (ecosystem, name)? = Self.split(key) else { return }
                group.addTask {
                    (key, await RegistryMetadata.fetch(
                        ecosystem: ecosystem, name: name, floor: floors[key]?.floor, keep: floors[key]?.keep ?? [], cached: cache[key],
                        http: http, now: date
                    ))
                }
            }
            // Niet honderden verzoeken tegelijk: hooguit acht lopen er.
            for _ in 0..<Self.registryConcurrency { addNext() }
            for await (key, metadata) in group {
                if let metadata { result[key] = metadata }
                addNext()
            }
        }
        return result
    }

    /// "npm:@scope/naam" → ("npm", "@scope/naam").
    static func split(_ key: String) -> (String, String)? {
        guard let colon = key.firstIndex(of: ":") else { return nil }
        return (String(key[..<colon]), String(key[key.index(after: colon)...]))
    }

    /// Stap 6: haalt in rondes op wat `VersionReport.updateNeeds()` nog mist, elk ding één keer.
    func completingMetadata(
        _ start: [String: PackageMetadata], repos: [RepoVersions], latest: [String: PackageLatest],
        floors: [String: (floor: String, keep: Set<String>)], attempted: Set<String>, date: Date
    ) async -> [String: PackageMetadata] {
        var metadata = start
        var attemptedPackages = attempted
        var attemptedDetails: Set<DetailRequest> = []
        var attemptedLists: Set<String> = []
        let cache = metadataCache
        for _ in 0..<Self.metadataRounds {
            let needs = VersionReport(checkedAt: date, repos: repos, latestPackages: latest, packageMetadata: metadata).updateNeeds()
            let packages = needs.packages.subtracting(attemptedPackages)
            // Een register dat uit staat krijgt ook hier geen verzoek (de packages zelf filtert `fetchMetadata`).
            let lists = needs.versionLists.subtracting(attemptedLists).filter(isRegistryEnabled(key:))
            let details = needs.details.subtracting(attemptedDetails).filter { isRegistryEnabled(ecosystem: $0.ecosystem) }
            guard !packages.isEmpty || !lists.isEmpty || !details.isEmpty else { break }
            attemptedPackages.formUnion(packages)
            attemptedLists.formUnion(lists)
            attemptedDetails.formUnion(details)

            metadata.merge(await fetchMetadata(Array(packages), floors: floors, date: date)) { _, new in new }

            for key in lists.sorted() {
                guard case let (_, name)? = Self.split(key), var package = metadata[key],
                      let versions = await RegistryMetadata.goVersions(module: name, http: http, now: date) else { continue }
                for version in versions where package.versions[version] == nil { package.versions[version] = VersionMetadata() }
                package.isComplete = true
                metadata[key] = package.pruned(floor: floors[key]?.floor, keep: floors[key]?.keep ?? []).filling(from: cache[key])
            }

            let fetched = await withTaskGroup(of: (DetailRequest, VersionMetadata?).self) { group in
                var pending = details.sorted { ($0.key, $0.version) < ($1.key, $1.version) }.makeIterator()
                func addNext() {
                    guard let request = pending.next() else { return }
                    group.addTask {
                        (request, await RegistryMetadata.detail(ecosystem: request.ecosystem, name: request.name, version: request.version, http: http, now: date))
                    }
                }
                for _ in 0..<Self.registryConcurrency { addNext() }
                var result: [(DetailRequest, VersionMetadata)] = []
                for await (request, detail) in group {
                    if let detail { result.append((request, detail)) }
                    addNext()
                }
                return result
            }
            for (request, detail) in fetched {
                guard var version = metadata[request.key]?.versions[request.version] else { continue }
                version.dependencies = detail.dependencies ?? [:]
                version.runtimes.merge(detail.runtimes) { _, new in new }
                metadata[request.key]?.versions[request.version] = version
            }
        }
        return metadata
    }
}
