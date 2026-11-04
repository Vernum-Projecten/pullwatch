public import Foundation

/// De uitkomst van een hele versiecheck, zoals die in versions.json staat.
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
    let advisoryMisses: [String: Date]
    /// Wat de registers per versie zeggen, per `PackageUse.key`: voor de blokkades en de nieuwste
    /// bruikbare versie (`UpdateContext`), en als cache voor de volgende check (`VersionChecker`).
    public let packageMetadata: [String: PackageMetadata]
    /// Met welke versie van de check het rapport gemaakt is (`currentFormat`). Een ouder rapport
    /// mist wat de check sindsdien leest (transitieve packages, gevraagde bereiken, de Cargo.toml's
    /// van workspace-leden); de app checkt dan opnieuw (`isOutdatedFormat`).
    public let format: Int
    /// Wat de accounts in het register van hun dienst publiceren, één per account met de uitkomst
    /// (`PRProvider.publishedPackages`). Alleen de dagelijkse check vult het; leeg als de bron
    /// Packageregisters van je accounts uit stond.
    public let publishedPackages: [AccountPackages]

    /// 1: zonder `format`. 2: transitieve installs met hun ouder, de eisen uit elke Cargo.toml en
    /// de eis van de ouder uit het register.
    public static let currentFormat = 2

    public init(
        checkedAt: Date, repos: [RepoVersions], latestPackages: [String: PackageLatest] = [:],
        advisories: [String: GitHubAdvisory] = [:], advisoryMisses: [String: Date] = [:],
        packageMetadata: [String: PackageMetadata] = [:], format: Int = VersionReport.currentFormat,
        publishedPackages: [AccountPackages] = []
    ) {
        self.format = format
        self.publishedPackages = publishedPackages
        self.checkedAt = checkedAt
        self.latestPackages = latestPackages
        self.advisories = advisories
        self.advisoryMisses = advisoryMisses
        self.packageMetadata = packageMetadata
        self.repos = repos.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            if $0.advisoryCount != $1.advisoryCount { return $0.advisoryCount > $1.advisoryCount }
            return $0.repo.localizedCaseInsensitiveCompare($1.repo) == .orderedAscending
        }
    }

    private enum CodingKeys: String, CodingKey {
        case checkedAt, repos, latestPackages, advisories, advisoryMisses, packageMetadata, format, publishedPackages
    }

    /// versions.json van vóór het package-overzicht heeft geen `latestPackages`, van vóór de
    /// blokkades geen `packageMetadata`, van vóór de eigen packages geen `publishedPackages` (en
    /// wat daarvan niet te lezen is, valt weg in plaats van het hele rapport).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        checkedAt = try c.decode(Date.self, forKey: .checkedAt)
        repos = try c.decode([RepoVersions].self, forKey: .repos)
        latestPackages = try c.decodeIfPresent([String: PackageLatest].self, forKey: .latestPackages) ?? [:]
        advisories = try c.decodeIfPresent([String: GitHubAdvisory].self, forKey: .advisories) ?? [:]
        advisoryMisses = try c.decodeIfPresent([String: Date].self, forKey: .advisoryMisses) ?? [:]
        packageMetadata = try c.decodeIfPresent([String: PackageMetadata].self, forKey: .packageMetadata) ?? [:]
        format = try c.decodeIfPresent(Int.self, forKey: .format) ?? 1
        publishedPackages = ((try? c.decodeIfPresent([Lossy<AccountPackages>].self, forKey: .publishedPackages)) ?? []).compactMap(\.value)
    }

    /// Gemaakt door een oudere versie van de check: het zegt minder dan een nieuwe check zou zeggen.
    public var isOutdatedFormat: Bool { format < Self.currentFormat }
}

extension VersionReport {
    /// Vervangt één repo; `checkedAt` blijft het tijdstip van de laatste volledige check. Nieuwste
    /// versies uit `latest` komen erbij; bij een ongewijzigde versie of mislukte opzoeking blijft de oude.
    /// Metadata uit `metadata` vervangt die van hetzelfde package.
    public func replacing(
        _ repo: RepoVersions, latest: [String: PackageLatest] = [:], metadata: [String: PackageMetadata] = [:]
    ) -> VersionReport {
        let merged = latestPackages.merging(latest) { old, new in PackageLatest.keepsOld(old, over: new) ? old : new }
        // Een repo die bij de laatste volledige check nog niet gevolgd werd, komt erbij.
        let replaced = repos.contains { $0.id == repo.id } ? repos.map { $0.id == repo.id ? repo : $0 } : repos + [repo]
        return VersionReport(
            checkedAt: checkedAt, repos: replaced, latestPackages: merged, advisories: advisories, advisoryMisses: advisoryMisses,
            packageMetadata: packageMetadata.merging(metadata) { _, new in new }, format: format,
            publishedPackages: publishedPackages
        )
    }

    /// Vervangt of voegt meerdere repo's toe (`runMissing`), zoals `replacing(_:latest:metadata:)`.
    public func replacing(
        _ repos: [RepoVersions], latest: [String: PackageLatest] = [:], metadata: [String: PackageMetadata] = [:]
    ) -> VersionReport {
        var report = self
        for (index, repo) in repos.enumerated() {
            report = report.replacing(repo, latest: index == 0 ? latest : [:], metadata: index == 0 ? metadata : [:])
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
    /// voor een repo die er toen niet bij zat of waarvan de CVE-check toen mislukte of uit stond,
    /// telt alles als bekend: anders komt er een stortvloed aan meldingen.
    public func newVulnerabilities(since previous: VersionReport?) -> [(repo: String, vulnerability: Vulnerability)] {
        guard let previous else { return [] }
        let before = Dictionary(previous.repos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [(repo: String, vulnerability: Vulnerability)] = []
        for repo in repos {
            guard let old = before[repo.id], old.error == nil, old.vulnerabilityError == nil,
                  !old.isUnchecked(.osv), !repo.isUnchecked(.osv) else { continue }
            // Eén melding per lek en package, ook als het meerdere installs raakt; de directe
            // install (als die er is) staat in de melding.
            let known = Set(old.vulnerabilities.map(\.key))
            for advisory in repo.advisories where !known.contains(advisory.id) {
                result.append((repo.repo, advisory.first))
            }
        }
        return result
    }

    /// Het rapport zoals het getoond mag worden nu `disabled` uit staan: wat eerder van zo'n bron
    /// kwam, staat er niet meer als actueel, en de bron staat in `skippedSources` van elke repo
    /// waar hij iets had moeten controleren, met dezelfde regels als `VersionChecker.check`. Zo ziet
    /// het rapport eruit alsof de bronnen bij de laatste check al uit stonden. `accountKinds` geeft
    /// per account de dienst, voor de beveiliging van die dienst; een repo van een onbekend account
    /// houdt zijn beveiliging.
    public func visible(disabled: Set<DataSourceID>, accountKinds: [UUID: ProviderKind]) -> VersionReport {
        guard !disabled.isEmpty else { return self }
        let registriesOff = disabled.contains(.packageRegistries)
        /// Een eigen package hangt aan de bron Packageregisters van je accounts, niet aan het
        /// publieke register van zijn ecosysteem.
        func isOff(key: String) -> Bool {
            if packageMetadata[key]?.inHouse != nil { return registriesOff }
            return VersionChecker.split(key).flatMap { DataSourceID.registry(ecosystem: $0.0) }.map(disabled.contains) ?? false
        }
        let inHouseKeys = Set(packageMetadata.filter { $0.value.inHouse != nil }.keys)
        /// Onderdelen waarvan de releasebron uit staat: geen nieuwste versie en geen status.
        func components(_ components: [ComponentVersion]) -> (components: [ComponentVersion], skipped: Set<DataSourceID>) {
            var skipped: Set<DataSourceID> = []
            let result = components.map { component in
                let id = DataSourceID.releases(product: component.product)
                guard disabled.contains(id) else { return component }
                skipped.insert(id)
                return ComponentVersion(
                    product: component.product, label: component.label, version: component.version, latest: nil,
                    status: .unknown, sources: component.sources
                )
            }
            return (result, skipped)
        }
        /// OSV als er packages zijn, een register per gebruikt ecosysteem.
        func packageSources(hasPackages: Bool, ecosystems: Set<String>) -> Set<DataSourceID> {
            var skipped: Set<DataSourceID> = []
            if hasPackages, disabled.contains(.osv) { skipped.insert(.osv) }
            for ecosystem in ecosystems {
                if let id = DataSourceID.registry(ecosystem: ecosystem), disabled.contains(id) { skipped.insert(id) }
            }
            return skipped
        }

        let repos = repos.map { repo -> RepoVersions in
            let uses = repo.packages + repo.otherPackages
            let ecosystems = Set(uses.map(\.ecosystem))
            var skipped = repo.skippedSources.union(packageSources(hasPackages: !uses.isEmpty, ecosystems: ecosystems))
            if registriesOff, uses.contains(where: { inHouseKeys.contains($0.key) }) { skipped.insert(.packageRegistries) }
            let shown = components(repo.components)
            skipped.formUnion(shown.skipped)
            var security = repo.security
            if let id = accountKinds[repo.accountId].flatMap(VersionChecker.securitySource(for:)), disabled.contains(id) {
                security = nil
                skipped.insert(id)
            }
            // Van de release bewaart het rapport geen packages: die van de default branch en de
            // gevonden kwetsbaarheden van de tag staan ervoor. Liever een keer te vaak "niet
            // gecontroleerd" dan een oude "geen kwetsbaarheden".
            let release = repo.release.map { release -> ReleaseVersions in
                guard release.error == nil else { return release }
                let releaseShown = components(release.components)
                let releaseSkipped = release.skippedSources
                    .union(packageSources(
                        hasPackages: !uses.isEmpty || !release.vulnerabilities.isEmpty,
                        ecosystems: ecosystems.union(release.vulnerabilities.map(\.ecosystem))
                    ))
                    .union(releaseShown.skipped)
                return ReleaseVersions(
                    tag: release.tag, components: releaseShown.components,
                    vulnerabilities: disabled.contains(.osv) ? [] : release.vulnerabilities, error: release.error,
                    skippedSources: releaseSkipped
                )
            }
            let osvOff = disabled.contains(.osv)
            return RepoVersions(
                accountId: repo.accountId, repo: repo.repo, components: shown.components, error: repo.error,
                vulnerabilities: osvOff ? [] : repo.vulnerabilities,
                vulnerabilityError: osvOff ? nil : repo.vulnerabilityError,
                withdrawnVulnerabilities: osvOff ? [] : repo.withdrawnVulnerabilities,
                release: release, packages: repo.packages, otherPackages: repo.otherPackages, security: security,
                skippedSources: skipped
            )
        }
        return VersionReport(
            checkedAt: checkedAt, repos: repos,
            latestPackages: latestPackages.filter { !isOff(key: $0.key) },
            advisories: disabled.contains(.gitHubAdvisoryDatabase) ? [:] : advisories,
            advisoryMisses: advisoryMisses,
            packageMetadata: packageMetadata.compactMapValues { metadata in
                // Een eigen package met de bron uit: wel bekend als eigen, maar zonder versies.
                guard let own = metadata.inHouse else { return metadata }
                return registriesOff ? PackageMetadata(latest: nil, versions: [:], inHouse: own.with(status: .sourceOff)) : metadata
            }.filter { $0.value.inHouse != nil || !isOff(key: $0.key) }, format: format,
            publishedPackages: disabled.contains(.packageRegistries) ? [] : publishedPackages
        )
    }
}
