import Foundation

// MARK: - Eigen packages

extension VersionChecker {
    /// Welke dependencies eigen packages zijn (#214). Een sleutel is eigen als een actief account
    /// (bekend en niet gepauzeerd) een package met die naam publiceert en elke install ervan in
    /// deze check aantoonbaar uit dat register komt (`InHouseEvidence`): een scope van de
    /// eigenaar, of het register in de lockfile. Eén install zonder bewijs (een andere repo die
    /// het publieke package gebruikt) maakt de sleutel publiek: die install moet de publieke
    /// nieuwste versie en de CVE's van OSV krijgen, en de naam gaat dan toch al naar buiten.
    ///
    /// - Bron Packageregisters van je accounts uit: geen eigen register, dus ook geen nieuwste
    ///   versie. Wat de vorige check als eigen package kende (`metadataCache`), blijft eigen (met
    ///   bewijs en een actief account) en staat als "niet gecontroleerd: bron staat uit".
    /// - Het account mag het register niet (meer) lezen: wat het vorige keer publiceerde staat
    ///   als "niet gecontroleerd" met de reden.
    /// - Het register mislukte (netwerk) of het actieve account zat niet in deze check: de
    ///   metadata van de vorige check blijft.
    /// - Het account is weg of gepauzeerd, of noemt het package niet meer: niet meer eigen, de
    ///   check doet wat hij voor elk publiek package doet.
    func inHouseCheck(dependencies: [Dependency], published: [AccountPackages], accounts: [Account]) -> InHouseCheck {
        let byId = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func isActive(_ id: UUID) -> Bool { byId[id].map { !$0.isPaused } ?? false }
        let installs = Dictionary(grouping: dependencies, by: { "\($0.ecosystem):\($0.name)" })
        func isProven(_ key: String, owner: String, accountId: UUID) -> Bool {
            let found = installs[key] ?? []
            return !found.isEmpty && found.allSatisfy { InHouseEvidence.proves($0, owner: owner, account: byId[accountId]) }
        }
        /// Een eerdere check vond de naam in het publieke register, of wist dat al.
        func isPublicName(_ key: String) -> Bool {
            guard let old = metadataCache[key] else { return false }
            return old.inHouse?.isPublicName ?? (old.latest != nil)
        }
        let cached = metadataCache.filter { $0.value.inHouse != nil }
        var result = InHouseCheck()
        guard isEnabled(.packageRegistries) else {
            for key in installs.keys {
                guard let old = cached[key]?.inHouse, isActive(old.accountId), isProven(key, owner: old.owner, accountId: old.accountId) else { continue }
                result.metadata[key] = PackageMetadata(latest: nil, versions: [:], inHouse: old.with(status: .sourceOff))
            }
            return result
        }
        let active = published.filter { isActive($0.accountId) }
        let results = Dictionary(active.map { ($0.accountId, $0.result) }, uniquingKeysWith: { first, _ in first })
        let index = InHouseIndex(active.flatMap(\.result.packages), kinds: byId.mapValues(\.kind))
        for key in installs.keys {
            if let package = index.match(key: key) {
                let account = byId[package.accountId]
                let page = (package.repository.flatMap { account?.repoWebURL($0) } ?? account.flatMap { Self.projectURL(package, account: $0) })
                    .map(Self.withoutCredentials)
                let own = Self.metadata(of: package, repositoryURL: page)
                if isProven(key, owner: package.owner, accountId: package.accountId) {
                    result.metadata[key] = own.withInHouse(own.inHouse?.with(isPublicName: isPublicName(key)))
                } else if let namesake = own.inHouse {
                    result.namesakes[key] = namesake
                }
                continue
            }
            guard let old = cached[key], let inHouse = old.inHouse, isActive(inHouse.accountId),
                  isProven(key, owner: inHouse.owner, accountId: inHouse.accountId) else { continue }
            switch results[inHouse.accountId] {
            case .needsPermission(let reason)?:
                result.metadata[key] = PackageMetadata(latest: nil, versions: [:], inHouse: inHouse.with(status: .needsPermission(reason: reason)))
            case .failed?, nil:
                result.metadata[key] = old
            case .packages?, .notSupported?:
                // Het account zegt nu wat het publiceert, en dit package hoort er niet meer bij.
                continue
            }
        }
        return result
    }

    /// De metadata van een eigen package: de versies uit het eigen register (wat ze vragen staat
    /// daar niet, dus `dependencies` blijft onbekend) en de hoogste stabiele versie. Een zwevende
    /// tag of een image zonder tag is nooit de nieuwste versie (`releasedVersion`).
    static func metadata(of package: PublishedPackage, repositoryURL: URL?) -> PackageMetadata {
        var versions: [String: VersionMetadata] = [:]
        for version in package.versions { versions[version.version] = VersionMetadata() }
        // Op `Version`, zodat "v2.3.0" en "2.3.0" gelijk lezen en "1.10" na "1.9" komt.
        let stable = package.versions.compactMap { item in Version(item.version).map { (text: item.version, version: $0) } }
            .filter { !$0.version.isPrerelease }
        let latest = stable.max { $0.version < $1.version }?.text ?? package.releasedVersion
        if let latest, versions[latest] == nil { versions[latest] = VersionMetadata() }
        let inHouse = InHousePackage(
            accountId: package.accountId, name: package.name, type: package.type, owner: package.owner, repository: package.repository,
            repositoryURL: repositoryURL, registryURL: package.webURL
        )
        return PackageMetadata(latest: latest, versions: versions, inHouse: inHouse)
    }

    /// Azure Artifacts koppelt een package aan geen repository: de link gaat naar het project van
    /// de feed (`owner`), of de organisatie bij een feed van de organisatie.
    static func projectURL(_ package: PublishedPackage, account: Account) -> URL? {
        guard package.repository == nil, account.kind == .azureDevOps,
              let organization = URL(string: "https://dev.azure.com")?.appending(path: account.organization) else { return nil }
        return package.owner.caseInsensitiveCompare(account.organization) == .orderedSame
            ? organization : organization.appending(path: package.owner)
    }

    /// Een eigen server kan met inloggegevens in de URL ingesteld zijn; die komen niet in het rapport.
    static func withoutCredentials(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user != nil || components.password != nil else { return url }
        components.user = nil
        components.password = nil
        return components.url ?? url
    }

    /// Wat een account nu publiceert: het nieuwe resultaat, of bij een mislukt register dat van de
    /// vorige check (`previousPublished`), zodat één slechte dag een eigen package niet publiek maakt.
    func effectivePublished(_ fresh: [AccountPackages]) -> [AccountPackages] {
        let before = Dictionary(previousPublished.map { ($0.accountId, $0) }, uniquingKeysWith: { first, _ in first })
        return fresh.map { current in
            guard current.isFailed, let old = before[current.accountId], !old.isFailed else { return current }
            return old
        }
    }
}

extension PackageMetadata {
    /// Dezelfde metadata met een andere herkomst.
    func withInHouse(_ inHouse: InHousePackage?) -> PackageMetadata {
        var copy = self
        copy.inHouse = inHouse
        return copy
    }
}
