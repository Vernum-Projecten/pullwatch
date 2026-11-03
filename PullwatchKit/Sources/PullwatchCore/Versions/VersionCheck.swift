import Foundation

/// Eén onderdeel (taal, runtime, framework of Docker-image) van een repo met zijn status.
public struct ComponentVersion: Codable, Hashable, Sendable {
    public let product: String
    public let label: String
    /// Oudste gevonden versie als het onderdeel in meerdere bestanden staat.
    public let version: String
    public let latest: String?
    public let status: VersionStatus
    public let sources: [String]
    /// Releasecyclus van `version` (bv. "1.26") en de nieuwste patch daarin; nil als onbekend.
    public let cycle: String?
    public let cycleLatest: String?

    public init(
        product: String, label: String, version: String, latest: String?, status: VersionStatus, sources: [String],
        cycle: String? = nil, cycleLatest: String? = nil
    ) {
        self.product = product
        self.label = label
        self.version = version
        self.latest = latest
        self.status = status
        self.sources = sources
        self.cycle = cycle
        self.cycleLatest = cycleLatest
    }
}

/// Dezelfde check op de nieuwste tag: wat er in de laatste release zit.
public struct ReleaseVersions: Codable, Hashable, Sendable {
    public let tag: String
    public let components: [ComponentVersion]
    /// Ernstigste eerst.
    public let vulnerabilities: [Vulnerability]
    /// Gezet als de tag niet te scannen was; de check van de default branch staat dan nog wel.
    public let error: String?

    public init(tag: String, components: [ComponentVersion], vulnerabilities: [Vulnerability] = [], error: String? = nil) {
        self.tag = tag
        self.components = components
        self.vulnerabilities = vulnerabilities
        self.error = error
    }
}

public struct RepoVersions: Codable, Hashable, Sendable, Identifiable {
    public let accountId: UUID
    public let repo: String
    public let components: [ComponentVersion]
    public let error: String?
    /// Ernstigste eerst.
    public let vulnerabilities: [Vulnerability]
    /// Gezet als de CVE-check voor deze repo niet kon draaien (OSV onbereikbaar).
    public let vulnerabilityError: String?
    /// Check van de nieuwste tag; nil als de repo geen tags met een versienummer heeft. Alleen ter info:
    /// status, sortering en meldingen gaan over de default branch.
    public let release: ReleaseVersions?
    /// Direct gebruikte packages op de default branch, voor het overzicht per package; elk met al
    /// zijn installs (versies, workspaces, ook transitief).
    public let packages: [PackageUse]
    /// Packages die de repo nergens zelf vraagt (alleen transitief, of zonder manifest om het te
    /// bepalen), met hun installs; voor de repo-pagina en "alleen transitief" in Versies.
    public let otherPackages: [PackageUse]
    /// Beveiligingsgegevens van de dienst zelf (code scanning, geheimen, eigen adviezen, Advanced
    /// Security); nil als de dienst die niet kent of het ophalen mislukte.
    public let security: SecurityScan?

    public var id: String { "\(accountId.uuidString)/\(repo)" }

    /// Slechtste status van de onderdelen; een fout telt als onbekend. Alleen de default branch telt:
    /// wat daar al opgelost is, hoeft niet gemeld te worden.
    public var worstStatus: VersionStatus? {
        if error != nil { return .unknown }
        return components.map(\.status).max()
    }

    /// Voor sorteren: een kwetsbaarheid weegt even zwaar als EOL.
    public var severity: Int {
        max(worstStatus?.severity ?? -1, vulnerabilities.isEmpty ? -1 : VersionStatus.eol.severity)
    }

    /// Aantal adviezen (lek per package), hoeveel installs elk ook raakt.
    public var advisoryCount: Int { Set(vulnerabilities.map(\.key)).count }

    /// Zit deze kwetsbaarheid van de default branch ook in de laatste release? nil zonder (bruikbare) release.
    public func isInRelease(_ vulnerability: Vulnerability) -> Bool? {
        guard let release, release.error == nil else { return nil }
        return release.vulnerabilities.contains { $0.key == vulnerability.key }
    }

    public init(
        accountId: UUID,
        repo: String,
        components: [ComponentVersion],
        error: String? = nil,
        vulnerabilities: [Vulnerability] = [],
        vulnerabilityError: String? = nil,
        release: ReleaseVersions? = nil,
        packages: [PackageUse] = [],
        otherPackages: [PackageUse] = [],
        security: SecurityScan? = nil
    ) {
        self.accountId = accountId
        self.repo = repo
        self.components = components
        self.error = error
        self.vulnerabilities = vulnerabilities
        self.vulnerabilityError = vulnerabilityError
        self.release = release
        self.packages = packages
        self.otherPackages = otherPackages
        self.security = security
    }

    private enum CodingKeys: String, CodingKey {
        case accountId, repo, components, error, vulnerabilities, vulnerabilityError, release, packages, otherPackages, security
    }

    /// versions.json van vóór de CVE-check heeft geen `vulnerabilities`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try c.decode(UUID.self, forKey: .accountId)
        repo = try c.decode(String.self, forKey: .repo)
        components = try c.decode([ComponentVersion].self, forKey: .components)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        vulnerabilities = try c.decodeIfPresent([Vulnerability].self, forKey: .vulnerabilities) ?? []
        vulnerabilityError = try c.decodeIfPresent(String.self, forKey: .vulnerabilityError)
        release = try c.decodeIfPresent(ReleaseVersions.self, forKey: .release)
        packages = try c.decodeIfPresent([PackageUse].self, forKey: .packages) ?? []
        otherPackages = try c.decodeIfPresent([PackageUse].self, forKey: .otherPackages) ?? []
        security = try c.decodeIfPresent(SecurityScan.self, forKey: .security)
    }
}

public struct VersionReport: Codable, Equatable, Sendable {
    public let checkedAt: Date
    /// Slechtste status eerst, dan meeste kwetsbaarheden, dan alfabetisch.
    public let repos: [RepoVersions]
    /// Nieuwste versie per package (`PackageUse.key`) over alle repo's.
    public let latestPackages: [String: PackageLatest]
    /// Adviezen uit de GitHub Advisory Database per GHSA-id, één keer opgehaald voor alle repo's
    /// en checks (`VersionChecker.completingAdvisories`).
    public let advisories: [String: GitHubAdvisory]
    /// GHSA-ids en CVE's waar GitHub geen advies voor had, met het moment van vragen.
    public let advisoryMisses: [String: Date]

    public init(
        checkedAt: Date, repos: [RepoVersions], latestPackages: [String: PackageLatest] = [:],
        advisories: [String: GitHubAdvisory] = [:], advisoryMisses: [String: Date] = [:]
    ) {
        self.checkedAt = checkedAt
        self.latestPackages = latestPackages
        self.advisories = advisories
        self.advisoryMisses = advisoryMisses
        self.repos = repos.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            if $0.advisoryCount != $1.advisoryCount { return $0.advisoryCount > $1.advisoryCount }
            return $0.repo.localizedCaseInsensitiveCompare($1.repo) == .orderedAscending
        }
    }

    private enum CodingKeys: String, CodingKey {
        case checkedAt, repos, latestPackages, advisories, advisoryMisses
    }

    /// versions.json van vóór het package-overzicht heeft geen `latestPackages`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        checkedAt = try c.decode(Date.self, forKey: .checkedAt)
        repos = try c.decode([RepoVersions].self, forKey: .repos)
        latestPackages = try c.decodeIfPresent([String: PackageLatest].self, forKey: .latestPackages) ?? [:]
        advisories = try c.decodeIfPresent([String: GitHubAdvisory].self, forKey: .advisories) ?? [:]
        advisoryMisses = try c.decodeIfPresent([String: Date].self, forKey: .advisoryMisses) ?? [:]
    }
}

extension VersionReport {
    /// Vervangt één repo; `checkedAt` blijft het tijdstip van de laatste volledige check. Nieuwste
    /// versies uit `latest` komen erbij; bij een ongewijzigde versie of mislukte opzoeking blijft de oude.
    public func replacing(_ repo: RepoVersions, latest: [String: PackageLatest] = [:]) -> VersionReport {
        let merged = latestPackages.merging(latest) { old, new in PackageLatest.keepsOld(old, over: new) ? old : new }
        // Een repo die bij de laatste volledige check nog niet gevolgd werd, komt erbij.
        let replaced = repos.contains { $0.id == repo.id } ? repos.map { $0.id == repo.id ? repo : $0 } : repos + [repo]
        return VersionReport(
            checkedAt: checkedAt, repos: replaced, latestPackages: merged, advisories: advisories, advisoryMisses: advisoryMisses
        )
    }

    /// Vervangt of voegt meerdere repo's toe (`runMissing`), zoals `replacing(_:latest:)`.
    public func replacing(_ repos: [RepoVersions], latest: [String: PackageLatest] = [:]) -> VersionReport {
        var report = self
        for (index, repo) in repos.enumerated() {
            report = report.replacing(repo, latest: index == 0 ? latest : [:])
        }
        return report
    }

    /// Automatische check: eens per dag.
    public static let autoInterval: TimeInterval = 24 * 3600
    /// Na een volledig mislukte automatische check (bv. offline) opnieuw na een uur.
    public static let autoRetryInterval: TimeInterval = 3600

    /// Elke repo gaf een fout: geen bruikbaar resultaat (bv. geen netwerk).
    public var failedCompletely: Bool {
        !repos.isEmpty && repos.allSatisfy { $0.error != nil }
    }

    /// Kwetsbaarheden die in `previous` nog niet voor die repo bestonden. Zonder vorige check,
    /// voor een repo die er toen niet bij zat of waarvan de CVE-check toen mislukte, telt
    /// alles als bekend: anders komt er een stortvloed aan meldingen.
    public func newVulnerabilities(since previous: VersionReport?) -> [(repo: String, vulnerability: Vulnerability)] {
        guard let previous else { return [] }
        let before = Dictionary(previous.repos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [(repo: String, vulnerability: Vulnerability)] = []
        for repo in repos {
            guard let old = before[repo.id], old.error == nil, old.vulnerabilityError == nil else { continue }
            // Eén melding per lek en package, ook als het meerdere installs raakt; de directe
            // install (als die er is) staat in de melding.
            let known = Set(old.vulnerabilities.map(\.key))
            for advisory in repo.advisories where !known.contains(advisory.id) {
                result.append((repo.repo, advisory.first))
            }
        }
        return result
    }
}

/// Leest per gevolgde repo de projectbestanden, vergelijkt de gevonden versies met endoflife.date
/// en zoekt bekende kwetsbaarheden in de packages via OSV.dev.
public struct VersionChecker: Sendable {
    let makeProvider: @Sendable (Account) -> any PRProvider
    let http: any HTTPClient
    let now: @Sendable () -> Date

    public init(
        makeProvider: @escaping @Sendable (Account) -> any PRProvider,
        http: any HTTPClient = URLSessionHTTPClient(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.makeProvider = makeProvider
        self.http = http
        self.now = now
    }

    /// `progress(done, total)` na het bepalen van de repo's en na elke gescande repo.
    public func run(accounts: [Account], progress: @escaping @Sendable (Int, Int) async -> Void = { _, _ in }) async -> VersionReport {
        // 1. Gevolgde repo's per account.
        var targets: [(account: Account, provider: any PRProvider, repos: [String])] = []
        var results: [RepoVersions] = []
        for account in accounts {
            let provider = makeProvider(account)
            do {
                let repos = try await provider.listRepos().filter {
                    let watch = account.watch(for: $0)
                    return watch.prs || watch.tags || watch.completed
                }
                targets.append((account, provider, repos))
            } catch {
                results.append(RepoVersions(accountId: account.id, repo: account.displayName, components: [], error: Self.message(error)))
            }
        }

        let checked = await check(targets, progress: progress)
        return VersionReport(checkedAt: now(), repos: results + checked.repos, latestPackages: checked.latest)
    }

    /// Checkt één repo opnieuw, bv. na een fix; het resultaat vervangt de regel in het rapport
    /// (`VersionReport.replacing(_:latest:)`).
    public func run(account: Account, repo: String) async -> (repo: RepoVersions, latest: [String: PackageLatest]) {
        let checked = await check([(account, makeProvider(account), [repo])], progress: { _, _ in })
        return (checked.repos.first ?? RepoVersions(accountId: account.id, repo: repo, components: []), checked.latest)
    }

    /// Checkt alleen de gevolgde repo's die nog niet in `report` staan (net gevolgd of nieuw bij
    /// de dienst), zodat ze niet tot de volgende dagelijkse check op "Nog niet gecheckt" blijven.
    /// Een account waarvan de lijst niet lukt wordt overgeslagen. `progress` zoals bij `run(accounts:)`.
    public func runMissing(
        accounts: [Account],
        in report: VersionReport,
        progress: @escaping @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async -> (repos: [RepoVersions], latest: [String: PackageLatest]) {
        let known = Set(report.repos.map { "\($0.accountId.uuidString)/\($0.repo.lowercased())" })
        var targets: [(account: Account, provider: any PRProvider, repos: [String])] = []
        for account in accounts {
            let provider = makeProvider(account)
            guard let listed = try? await provider.listRepos() else { continue }
            let repos = listed.filter {
                let watch = account.watch(for: $0)
                return (watch.prs || watch.tags || watch.completed)
                    && !known.contains("\(account.id.uuidString)/\($0.lowercased())")
            }
            if !repos.isEmpty { targets.append((account, provider, repos)) }
        }
        guard !targets.isEmpty else { return ([], [:]) }
        return await check(targets, progress: progress)
    }

    /// Stap 2 t/m 5 voor de opgegeven repo's per account.
    private func check(
        _ targets: [(account: Account, provider: any PRProvider, repos: [String])],
        progress: @escaping @Sendable (Int, Int) async -> Void
    ) async -> (repos: [RepoVersions], latest: [String: PackageLatest]) {
        var results: [RepoVersions] = []
        // 2. Bestanden scannen; accounts parallel, repo's per account na elkaar.
        let total = targets.reduce(0) { $0 + $1.repos.count }
        let counter = Counter()
        await progress(0, total)
        let scanned = await withTaskGroup(of: [ScannedRepo].self) { group in
            for target in targets {
                group.addTask {
                    var out: [ScannedRepo] = []
                    for repo in target.repos {
                        let found: Result<RepoScan, any Error>
                        do {
                            found = .success(try await Self.scanWithRelease(repo: repo, provider: target.provider))
                        } catch {
                            found = .failure(error)
                        }
                        // Code scanning, geheimen, eigen adviezen: los van de bestanden, ook als die mislukten.
                        let security = try? await target.provider.securityAlerts(in: repo)
                        out.append(ScannedRepo(accountId: target.account.id, repo: repo, found: found, security: security))
                        await progress(await counter.increment(), total)
                    }
                    return out
                }
            }
            return await group.reduce(into: []) { $0 += $1 }
        }

        // 3. Releases per product, één keer per check.
        let scans = scanned.flatMap { item -> [Scan] in
            guard let repoScan = try? item.found.get() else { return [] }
            return [repoScan.main] + ((try? repoScan.release?.found.get()).map { [$0] } ?? [])
        }
        let products = Set(scans.flatMap { $0.versions.map(\.product) })
        let releases = await withTaskGroup(of: (String, [EndOfLifeRelease]?).self) { group in
            for product in products {
                group.addTask { (product, try? await EndOfLife.releases(product: product, http: http, now: now())) }
            }
            return await group.reduce(into: [String: [EndOfLifeRelease]]()) { $0[$1.0] = $1.1 }
        }

        // 4. Kwetsbaarheden: één batch voor alle unieke naam@versie, daarna details per id. Elke
        //    install krijgt daarna het resultaat van zijn naam@versie.
        let dependencies = Set(scans.flatMap(\.dependencies).map(\.withoutSource))
            .sorted { ($0.ecosystem, $0.name, $0.version) < ($1.ecosystem, $1.name, $1.version) }
        var vulnerabilityIds: [Dependency: [String]] = [:]
        var osvError: String?
        var records: [String: OSVRecord] = [:]
        if !dependencies.isEmpty {
            do {
                let ids = try await OSV.query(dependencies, http: http, now: now())
                vulnerabilityIds = Dictionary(uniqueKeysWithValues: zip(dependencies, ids))
                let allIds = Set(ids.joined())
                let fetched = await OSV.records(ids: allIds, http: http, now: now())
                records = fetched.records
                if fetched.failed > 0 {
                    osvError = String(localized: "CVE-check onvolledig, details ontbreken: \(fetched.failed) van \(allIds.count)", bundle: .localizedCore, comment: "Aantal kwetsbaarheden zonder details, totaal")
                }
            } catch {
                osvError = String(localized: "CVE-check mislukt: \(Self.message(error))", bundle: .localizedCore, comment: "Foutmelding")
            }
        }

        // 4b. Nieuwste versie per direct gebruikt package op de default branch, één keer per package,
        //     hoeveel installs en versies het ook heeft.
        let mainScans = scanned.compactMap { try? $0.found.get().main }
        let packages = Dictionary(mainScans.flatMap(\.directDependencies).map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let checkedAt = now()
        var latest: [String: PackageLatest] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            var pending = packages.values.makeIterator()
            func addNext() {
                guard let package = pending.next() else { return }
                group.addTask {
                    (package.key, await PackageRegistry.latest(ecosystem: package.ecosystem, name: package.name, http: http, now: checkedAt))
                }
            }
            // Niet honderden verzoeken tegelijk: hooguit acht lopen er.
            for _ in 0..<Self.registryConcurrency { addNext() }
            for await (key, version) in group {
                latest[key] = PackageLatest(version: version, seenAt: checkedAt)
                addNext()
            }
        }

        // 5. Per repo samenvoegen en beoordelen.
        let date = now()
        func components(_ scan: Scan) -> [ComponentVersion] {
            Self.combine(scan.versions).map { detected, sources in
                let productReleases = releases[detected.product].flatMap { $0 }
                let evaluation = productReleases
                    .map { EndOfLife.evaluate(version: detected.version, releases: $0, now: date) }
                    ?? (status: .unknown, latest: nil)
                let cycle = productReleases.flatMap { EndOfLife.cycle(of: detected.version, releases: $0) }
                return ComponentVersion(
                    product: detected.product,
                    label: detected.label,
                    version: detected.version,
                    latest: evaluation.latest,
                    status: evaluation.status,
                    sources: sources,
                    cycle: cycle?.name,
                    cycleLatest: cycle.map { $0.latest ?? $0.name }
                )
            }
        }
        func vulnerabilities(_ scan: Scan) -> [Vulnerability] {
            OSV.vulnerabilities(
                dependencies: scan.dependencies,
                ids: scan.dependencies.map { vulnerabilityIds[$0.withoutSource] ?? [] },
                records: records
            )
        }
        for item in scanned {
            switch item.found {
            case .failure(let error):
                results.append(RepoVersions(
                    accountId: item.accountId, repo: item.repo, components: [], error: Self.message(error), security: item.security
                ))
            case .success(let repoScan):
                let release = repoScan.release.map { tag, found in
                    switch found {
                    case .success(let scan):
                        ReleaseVersions(tag: tag, components: components(scan), vulnerabilities: vulnerabilities(scan))
                    case .failure(let error):
                        ReleaseVersions(tag: tag, components: [], error: Self.message(error))
                    }
                }
                results.append(RepoVersions(
                    accountId: item.accountId,
                    repo: item.repo,
                    components: components(repoScan.main),
                    vulnerabilities: vulnerabilities(repoScan.main),
                    vulnerabilityError: repoScan.main.dependencies.isEmpty ? nil : osvError,
                    release: release,
                    packages: repoScan.main.directDependencies,
                    otherPackages: repoScan.main.otherPackages,
                    security: item.security
                ))
            }
        }
        return (results, latest)
    }

    static let registryConcurrency = 8

    struct ScannedRepo: Sendable {
        let accountId: UUID
        let repo: String
        let found: Result<RepoScan, any Error>
        let security: SecurityScan?
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

    private static func scanWithRelease(repo: String, provider: any PRProvider) async throws -> RepoScan {
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
            scan.versions += StackDetector.detect(path: path, content: content)
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

    static func isOlder(_ a: String, than b: String) -> Bool {
        let (x, y) = (a.split(separator: ".").map { Int($0) ?? 0 }, b.split(separator: ".").map { Int($0) ?? 0 })
        for i in 0..<max(x.count, y.count) {
            let (l, r) = (i < x.count ? x[i] : 0, i < y.count ? y[i] : 0)
            if l != r { return l < r }
        }
        return false
    }

    private static func message(_ error: any Error) -> String {
        (error as? ProviderError)?.userMessage ?? error.localizedDescription
    }
}

private actor Counter {
    private var value = 0
    func increment() -> Int {
        value += 1
        return value
    }
}
