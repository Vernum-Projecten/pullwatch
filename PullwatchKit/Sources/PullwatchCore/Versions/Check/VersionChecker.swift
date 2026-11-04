public import Foundation

/// Leest per gevolgde repo de projectbestanden, vergelijkt de gevonden versies met endoflife.date
/// en zoekt bekende kwetsbaarheden in de packages via OSV.dev.
public struct VersionChecker: Sendable {
    let makeProvider: @Sendable (Account) -> any PRProvider
    let http: any HTTPClient
    let now: @Sendable () -> Date
    /// `VersionReport.packageMetadata` van de vorige check: wat daarin per versie al opgehaald
    /// is (dependencies, een go.mod), gaat niet opnieuw de deur uit.
    let metadataCache: [String: PackageMetadata]
    /// Bronnen die uit staan (`AppConfig.disabledSources`): daar gaat geen verzoek heen.
    let disabledSources: Set<DataSourceID>
    /// `VersionReport.publishedPackages` van de vorige check: de eigen packages voor de check van
    /// één repo of van net gevolgde repo's (die vragen de registers niet opnieuw), en voor een
    /// account waarvan het register nu mislukt.
    let previousPublished: [AccountPackages]
    /// De accounts, voor de webpagina van de repository die een eigen package publiceert.
    let knownAccounts: [Account]

    public init(
        makeProvider: @escaping @Sendable (Account) -> any PRProvider,
        http: any HTTPClient = URLSessionHTTPClient(),
        now: @escaping @Sendable () -> Date = { Date() },
        metadataCache: [String: PackageMetadata] = [:],
        disabledSources: Set<DataSourceID> = [],
        publishedPackages: [AccountPackages] = [],
        accounts: [Account] = []
    ) {
        self.makeProvider = makeProvider
        self.http = http
        self.now = now
        self.metadataCache = metadataCache
        self.disabledSources = disabledSources
        self.previousPublished = publishedPackages
        self.knownAccounts = accounts
    }

    func isEnabled(_ id: DataSourceID) -> Bool { !disabledSources.contains(id) }

    /// Mag het register van dit ecosysteem gevraagd worden? Een ecosysteem zonder eigen bron
    /// (bv. Swift-packages per URL) valt onder geen schakelaar.
    func isRegistryEnabled(ecosystem: String) -> Bool {
        DataSourceID.registry(ecosystem: ecosystem).map(isEnabled) ?? true
    }

    /// Als `isRegistryEnabled(ecosystem:)`, voor een `PackageUse.key` ("ecosysteem:naam").
    func isRegistryEnabled(key: String) -> Bool {
        Self.split(key).map { isRegistryEnabled(ecosystem: $0.0) } ?? true
    }

    /// De bron achter `PRProvider.securityAlerts(in:)` voor een dienst; nil als de dienst die niet
    /// kent. GitHub Enterprise valt onder GitHub-beveiliging.
    static func securitySource(for kind: ProviderKind) -> DataSourceID? {
        switch kind {
        case .gitHub: .gitHubSecurity
        case .azureDevOps: .azureDevOpsAdvancedSecurity
        case .gitLab, .bitbucket, .gitea: nil
        }
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

        // De eigen packages vóór de scan: één lijst per account, niet per repo. De check heeft ze
        // nodig om een eigen package niet bij het publieke register op te zoeken.
        let published = await publishedPackages(targets)
        let checked = await check(targets, published: effectivePublished(published), progress: progress)
        return VersionReport(
            checkedAt: now(), repos: results + checked.repos, latestPackages: checked.latest, packageMetadata: checked.metadata,
            publishedPackages: published
        )
    }

    /// Wat elk account in het register van zijn dienst publiceert, voor zijn gevolgde repo's. Met de
    /// bron Packageregisters van je accounts uit gaat er geen verzoek de deur uit. Een dienst zonder
    /// register staat er als `.notSupported`; een fout wordt `.failed`, nooit een mislukte check.
    func publishedPackages(_ targets: [(account: Account, provider: any PRProvider, repos: [String])]) async -> [AccountPackages] {
        guard isEnabled(.packageRegistries) else { return [] }
        return await withTaskGroup(of: AccountPackages.self) { group in
            for target in targets {
                group.addTask {
                    let result: PublishedPackages
                    do {
                        result = try await target.provider.publishedPackages(followedRepos: target.repos)
                    } catch {
                        result = .failed(message: Self.message(error))
                    }
                    return AccountPackages(accountId: target.account.id, result: result, checkedAt: now())
                }
            }
            let all = await group.reduce(into: [AccountPackages]()) { $0.append($1) }
            // In de volgorde van de accounts, niet in die waarin ze klaar waren.
            let order = Dictionary(targets.enumerated().map { ($1.account.id, $0) }, uniquingKeysWith: { first, _ in first })
            return all.sorted { (order[$0.accountId] ?? 0) < (order[$1.accountId] ?? 0) }
        }
    }

    /// Checkt één repo opnieuw, bv. na een fix; het resultaat vervangt de regel in het rapport
    /// (`VersionReport.replacing(_:latest:metadata:)`).
    public func run(
        account: Account, repo: String
    ) async -> (repo: RepoVersions, latest: [String: PackageLatest], metadata: [String: PackageMetadata]) {
        let checked = await check([(account, makeProvider(account), [repo])], published: previousPublished, progress: { _, _ in })
        return (checked.repos.first ?? RepoVersions(accountId: account.id, repo: repo, components: []), checked.latest, checked.metadata)
    }

    /// Checkt alleen de gevolgde repo's die nog niet in `report` staan (net gevolgd of nieuw bij
    /// de dienst), zodat ze niet tot de volgende dagelijkse check op "Nog niet gecheckt" blijven.
    /// Een account waarvan de lijst niet lukt wordt overgeslagen. `progress` zoals bij `run(accounts:)`.
    public func runMissing(
        accounts: [Account],
        in report: VersionReport,
        progress: @escaping @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async -> (repos: [RepoVersions], latest: [String: PackageLatest], metadata: [String: PackageMetadata]) {
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
        guard !targets.isEmpty else { return ([], [:], [:]) }
        return await check(targets, published: previousPublished, progress: progress)
    }

    /// Stap 2 t/m 6 voor de opgegeven repo's per account; `published` zijn de eigen packages.
    private func check(
        _ targets: [(account: Account, provider: any PRProvider, repos: [String])],
        published: [AccountPackages],
        progress: @escaping @Sendable (Int, Int) async -> Void
    ) async -> (repos: [RepoVersions], latest: [String: PackageLatest], metadata: [String: PackageMetadata]) {
        var results: [RepoVersions] = []
        // 2. Bestanden scannen; accounts parallel, repo's per account na elkaar.
        let total = targets.reduce(0) { $0 + $1.repos.count }
        let counter = Counter()
        await progress(0, total)
        let scanned = await withTaskGroup(of: [ScannedRepo].self) { group in
            for target in targets {
                group.addTask {
                    var out: [ScannedRepo] = []
                    // Staat de beveiliging van deze dienst uit, dan vraagt de check er niet naar.
                    let securitySource = Self.securitySource(for: target.account.kind)
                    let securityOff = securitySource.map { !isEnabled($0) } ?? false
                    for repo in target.repos {
                        let found: Result<RepoScan, any Error>
                        do {
                            found = .success(try await Self.scanWithRelease(repo: repo, provider: target.provider))
                        } catch {
                            found = .failure(error)
                        }
                        // Code scanning, geheimen, eigen adviezen: los van de bestanden, ook als die mislukten.
                        let security = securityOff ? nil : try? await target.provider.securityAlerts(in: repo)
                        out.append(ScannedRepo(
                            accountId: target.account.id, repo: repo, found: found, security: security,
                            skipped: securityOff ? Set(securitySource.map { [$0] } ?? []) : []
                        ))
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
        // Een product waarvan de releasebron (endoflife.date, swift.org) uit staat, wordt niet gevraagd
        // en blijft `.unknown`; de repo krijgt die bron in `skippedSources`.
        let products = Set(scans.flatMap { $0.versions.map(\.product) }).filter { isEnabled(DataSourceID.releases(product: $0)) }
        let releases = await withTaskGroup(of: (String, [EndOfLifeRelease]?).self) { group in
            for product in products {
                group.addTask { (product, try? await EndOfLife.releases(product: product, http: http, now: now())) }
            }
            return await group.reduce(into: [String: [EndOfLifeRelease]]()) { $0[$1.0] = $1.1 }
        }

        // 3b. Eigen packages: wat een gevolgde repo zelf publiceert, krijgt zijn versies uit het
        //     eigen register. Die namen gaan hierna naar geen publiek register en niet naar OSV.
        let inHouse = inHouseMetadata(
            keys: Set(scans.flatMap(\.dependencies).map { "\($0.ecosystem):\($0.name)" }), published: published,
            accounts: targets.map(\.account) + knownAccounts
        )

        // 4. Kwetsbaarheden: één batch voor alle unieke naam@versie, daarna details per id. Elke
        //    install krijgt daarna het resultaat van zijn naam@versie.
        let dependencies = Set(scans.flatMap(\.dependencies).filter { inHouse["\($0.ecosystem):\($0.name)"] == nil }.map(\.withoutSource))
            .sorted { ($0.ecosystem, $0.name, $0.version) < ($1.ecosystem, $1.name, $1.version) }
        var vulnerabilityIds: [Dependency: [String]] = [:]
        var osvError: String?
        var records: [String: OSVRecord] = [:]
        // Met OSV uit gaat er niets de deur uit; repo's met packages krijgen `.osv` in `skippedSources`.
        if !dependencies.isEmpty, isEnabled(.osv) {
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

        // 4b. Nieuwste versie en metadata per versie (`RegistryMetadata`) per direct gebruikt package
        //     op de default branch, één document per package, hoeveel installs en versies het ook heeft.
        let mainScans = scanned.compactMap { try? $0.found.get().main }
        let packages = Dictionary(mainScans.flatMap(\.directDependencies).map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let floors = Self.floors(mainScans.flatMap(\.dependencies))
        let checkedAt = now()
        var latest: [String: PackageLatest] = [:]
        // Packages van een register dat uit staat krijgen geen nieuwste versie: daar zegt de check niets over.
        let checkable = packages.keys.filter { inHouse[$0] == nil && isRegistryEnabled(key: $0) }
        var metadata = await fetchMetadata(checkable, floors: floors, date: checkedAt, excluding: Set(inHouse.keys))
        for key in checkable {
            latest[key] = PackageLatest(version: metadata[key]?.latest, seenAt: checkedAt)
        }
        metadata.merge(inHouse) { _, own in own }
        for (key, own) in inHouse {
            latest[key] = PackageLatest(version: own.latest, seenAt: checkedAt)
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
        /// Bronnen die voor deze scan iets hadden moeten controleren maar uit stonden.
        func skippedSources(_ scan: Scan) -> Set<DataSourceID> {
            var skipped: Set<DataSourceID> = []
            if !scan.dependencies.isEmpty, !isEnabled(.osv) { skipped.insert(.osv) }
            // Een register alleen als de scan een package van dat ecosysteem gebruikt, een releasebron
            // alleen als er een onderdeel van dat product is.
            for ecosystem in Set(scan.dependencies.map(\.ecosystem)) {
                if let id = DataSourceID.registry(ecosystem: ecosystem), !isEnabled(id) { skipped.insert(id) }
            }
            // Een eigen package zonder eigen register: de bron Packageregisters van je accounts.
            if scan.dependencies.contains(where: { inHouse["\($0.ecosystem):\($0.name)"]?.inHouse?.status == .sourceOff }) {
                skipped.insert(.packageRegistries)
            }
            for product in Set(scan.versions.map(\.product)) {
                let id = DataSourceID.releases(product: product)
                if !isEnabled(id) { skipped.insert(id) }
            }
            return skipped
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
                    accountId: item.accountId, repo: item.repo, components: [], error: Self.message(error), security: item.security,
                    skippedSources: item.skipped
                ))
            case .success(let repoScan):
                let release = repoScan.release.map { tag, found in
                    switch found {
                    case .success(let scan):
                        ReleaseVersions(
                            tag: tag, components: components(scan), vulnerabilities: vulnerabilities(scan).filter { !$0.isWithdrawn },
                            skippedSources: skippedSources(scan)
                        )
                    case .failure(let error):
                        ReleaseVersions(tag: tag, components: [], error: Self.message(error))
                    }
                }
                let found = vulnerabilities(repoScan.main)
                results.append(RepoVersions(
                    accountId: item.accountId,
                    repo: item.repo,
                    components: components(repoScan.main),
                    vulnerabilities: found.filter { !$0.isWithdrawn },
                    vulnerabilityError: repoScan.main.dependencies.isEmpty ? nil : osvError,
                    withdrawnVulnerabilities: found.filter(\.isWithdrawn),
                    release: release,
                    packages: repoScan.main.directDependencies,
                    otherPackages: repoScan.main.otherPackages,
                    security: item.security,
                    skippedSources: item.skipped.union(skippedSources(repoScan.main))
                ))
            }
        }

        // 6. Wat de blokkades nog missen: ouders van transitieve installs, de dependencies van
        //    een paar versies (binair zoeken naar de laagste ouder die past), een go.mod of de
        //    versielijst van een Go-module. Per ronde alleen wat de vorige ronde vroeg.
        metadata = await completingMetadata(
            metadata, repos: results, latest: latest, floors: floors, attempted: Set(packages.keys), inHouse: Set(inHouse.keys), date: checkedAt
        )
        return (results, latest, metadata)
    }

    static let registryConcurrency = 8
    /// Hoeveel keer de check ontbrekende metadata ophaalt; binair zoeken in ~250 versies past erin.
    static let metadataRounds = 8

    /// Getal voor getal ("1.10" na "1.9"); wat geen getal is telt als 0.
    static func isOlder(_ a: String, than b: String) -> Bool {
        Version.compare(a.split(separator: ".").map { Int($0) ?? 0 }, b.split(separator: ".").map { Int($0) ?? 0 }) == .orderedAscending
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
