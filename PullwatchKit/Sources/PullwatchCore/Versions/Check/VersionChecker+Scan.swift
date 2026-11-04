import Foundation

// MARK: - De bestanden van een repo lezen

extension VersionChecker {
    struct ScannedRepo: Sendable {
        let accountId: UUID
        let repo: String
        let found: Result<RepoScan, any Error>
        let security: SecurityScan?
        /// Bronnen die al bij het scannen overgeslagen zijn (de beveiliging van de dienst).
        let skipped: Set<DataSourceID>
    }

    struct Scan: Sendable {
        var versions: [DetectedVersion] = []
        /// Eén per install (package, versie en workspace).
        var dependencies: [Dependency] = []
        /// Direct gevraagde namen per ecosysteem uit package.json, composer.json, pyproject.toml en
        /// Cargo.toml, over de hele repo.
        var manifests: [String: Set<String>] = [:]

        var directDependencies: [PackageUse] {
            DependencyDetector.direct(dependencies, manifests: manifests)
        }

        /// Wat niet in `directDependencies` staat, per package met al zijn installs, op volgorde van vinden.
        var otherPackages: [PackageUse] {
            let direct = Set(directDependencies.map(\.key))
            var order: [String] = []
            var installs: [String: (ecosystem: String, name: String, installs: [PackageInstall])] = [:]
            for dependency in dependencies {
                let key = "\(dependency.ecosystem):\(dependency.name)"
                guard !direct.contains(key) else { continue }
                if installs[key] == nil {
                    order.append(key)
                    installs[key] = (dependency.ecosystem, dependency.name, [])
                }
                if installs[key]?.installs.contains(dependency.install) == false { installs[key]?.installs.append(dependency.install) }
            }
            return order.compactMap { key in installs[key].map { PackageUse(ecosystem: $0.ecosystem, name: $0.name, installs: $0.installs) } }
        }
    }

    /// Default branch plus, als de repo tags heeft, de nieuwste tag.
    struct RepoScan: Sendable {
        var main: Scan
        var release: (tag: String, found: Result<Scan, any Error>)?
    }

    static func scanWithRelease(repo: String, provider: any PRProvider) async throws -> RepoScan {
        var result = RepoScan(main: try await scan(repo: repo, ref: nil, provider: provider))
        let tag: String?
        do {
            let fetch = try await provider.tags(in: [repo])
            tag = latestTag(fetch.tags.filter { $0.repo == repo }.map(\.name))
        } catch {
            return result // zonder tags blijft het bij de default branch
        }
        if let tag {
            do {
                result.release = (tag, .success(try await scan(repo: repo, ref: tag, provider: provider)))
            } catch {
                result.release = (tag, .failure(error))
            }
        }
        return result
    }

    /// Tag met het hoogste versienummer; pre-releases (`-rc1`, `beta`) alleen als er niets anders is.
    /// Tags zonder cijfers tellen niet.
    static func latestTag(_ names: [String]) -> String? {
        let versioned = names.compactMap { name in StackDetector.version(from: name).map { (name: name, version: $0) } }
        let isPrerelease = { (name: String) in
            name.range(of: #"-|alpha|beta|rc|pre|preview"#, options: [.regularExpression, .caseInsensitive],
                       range: name.firstIndex(where: \.isNumber).map { $0..<name.endIndex }) != nil
        }
        let finals = versioned.filter { !isPrerelease($0.name) }
        let candidates = finals.isEmpty ? versioned : finals
        return candidates.reduce(nil as (name: String, version: String)?) { best, item in
            guard let best else { return item }
            // Gelijke versie (rc1/rc2): de naam beslist, met getallen als getal.
            let newer = isOlder(best.version, than: item.version)
                || (!isOlder(item.version, than: best.version) && best.name.compare(item.name, options: .numeric) == .orderedAscending)
            return newer ? item : best
        }?.name
    }

    /// De bestanden die een scan leest, hoogstens `StackDetector.maxFiles` (één verzoek per bestand).
    /// Bij meer gaan lockfiles voor: zonder lockfile geen CVE's; de volgorde van de lijst blijft.
    static func selectedFiles(_ paths: [String]) -> [String] {
        let relevant = paths.filter { StackDetector.isRelevant($0) || (DependencyDetector.isRelevant($0) && !StackDetector.isIgnored($0)) }
        guard relevant.count > StackDetector.maxFiles else { return relevant }
        let isLock = { (path: String) in DependencyDetector.isLockfile(path.split(separator: "/").last.map(String.init) ?? path) }
        let chosen = Set((relevant.filter(isLock) + relevant.filter { !isLock($0) }).prefix(StackDetector.maxFiles))
        return relevant.filter(chosen.contains)
    }

    private static func scan(repo: String, ref: String?, provider: any PRProvider) async throws -> Scan {
        let paths = selectedFiles(try await provider.filePaths(in: repo, ref: ref))
        var scan = Scan()
        var replacedGoModules: Set<String> = []
        var dependencyFiles: [(path: String, content: String)] = []
        for path in paths {
            // Een bestand dat tussen lijst en lezen verdween telt niet; elke andere fout (rate limit,
            // netwerk) zou stil minder versies en CVE's opleveren, dus die faalt de hele repo.
            let content: String
            do {
                content = try await provider.fileContent(in: repo, path: path, ref: ref)
            } catch ProviderError.server(status: 404) {
                continue
            }
            // Een Cargo.toml van een lid telt alleen voor de packages; de rust-version staat in de root.
            if StackDetector.isRelevant(path) { scan.versions += StackDetector.detect(path: path, content: content) }
            dependencyFiles.append((path, content))
            if path.hasSuffix("go.mod") {
                replacedGoModules.formUnion(StackDetector.localGoReplacements(path: path, content: content))
            }
        }
        (scan.dependencies, scan.manifests) = DependencyDetector.installs(dependencyFiles)
        scan.versions.removeAll { detected in
            detected.product == "go" && replacedGoModules.contains(detected.source.split(separator: "/").dropLast().joined(separator: "/"))
        }
        // Een minimum (">=20") valt weg als dezelfde taal ergens vastgezet is (Docker, .nvmrc, toolchain).
        let pinned = Set(scan.versions.filter { !$0.isMinimum }.map(\.product))
        scan.versions.removeAll { $0.isMinimum && pinned.contains($0.product) }
        scan.versions = scan.versions.map { detected in
            guard let names = StackDetector.lockedPackages[detected.product],
                  let locked = scan.dependencies.first(where: { names.contains($0.name) && $0.scope == .direct })
                    ?? scan.dependencies.first(where: { names.contains($0.name) }) else { return detected }
            return DetectedVersion(product: detected.product, label: detected.label, version: locked.version, source: locked.source)
        }
        return scan
    }

    /// Eén onderdeel per label met de oudste versie; bronnen ontdubbeld, op volgorde van vinden.
    static func combine(_ found: [DetectedVersion]) -> [(DetectedVersion, [String])] {
        var order: [String] = []
        var oldest: [String: DetectedVersion] = [:]
        var sources: [String: [String]] = [:]
        for item in found {
            if oldest[item.label] == nil { order.append(item.label) }
            if let current = oldest[item.label] {
                if isOlder(item.version, than: current.version) { oldest[item.label] = item }
            } else {
                oldest[item.label] = item
            }
            if !(sources[item.label] ?? []).contains(item.source) { sources[item.label, default: []].append(item.source) }
        }
        return order.map { (oldest[$0]!, sources[$0] ?? []) }
    }
}
