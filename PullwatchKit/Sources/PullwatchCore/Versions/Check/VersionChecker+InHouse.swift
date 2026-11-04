import Foundation

// MARK: - Eigen packages

extension VersionChecker {
    /// De metadata van elke dependency in `keys` ("ecosysteem:naam") die een gevolgde repo zelf
    /// publiceert, uit de eigen registers in `published`. Deze namen gaan nooit naar het publieke
    /// register (npmjs.com, nuget.org, pypi.org, rubygems.org) of naar OSV: een private naam lekt
    /// zo niet, en een publiek package met dezelfde naam wordt niet voor het eigen aangezien.
    ///
    /// - Bron Packageregisters van je accounts uit: geen eigen register, dus ook geen nieuwste
    ///   versie. Wat de vorige check als eigen package kende (`metadataCache`), blijft eigen en
    ///   staat als "niet gecontroleerd: bron staat uit", nooit als actueel.
    /// - Het account mag het register niet (meer) lezen: wat het vorige keer publiceerde staat
    ///   als "niet gecontroleerd" met de reden.
    /// - Het register mislukte (netwerk) of het account zat niet in deze check: de metadata van
    ///   de vorige check blijft.
    /// - Een naam die geen gevolgde repo publiceert: nil, de check doet wat hij altijd deed.
    func inHouseMetadata(keys: Set<String>, published: [AccountPackages], accounts: [Account]) -> [String: PackageMetadata] {
        let cached = metadataCache.filter { $0.value.inHouse != nil }
        guard isEnabled(.packageRegistries) else {
            var result: [String: PackageMetadata] = [:]
            for key in keys {
                guard let old = cached[key]?.inHouse else { continue }
                result[key] = PackageMetadata(latest: nil, versions: [:], inHouse: old.with(status: .sourceOff))
            }
            return result
        }
        let results = Dictionary(published.map { ($0.accountId, $0.result) }, uniquingKeysWith: { first, _ in first })
        let webPages = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let index = InHouseIndex(published.flatMap(\.result.packages), kinds: webPages.mapValues(\.kind))
        var result: [String: PackageMetadata] = [:]
        for key in keys {
            if let package = index.match(key: key) {
                let account = webPages[package.accountId]
                let page = (package.repository.flatMap { account?.repoWebURL($0) } ?? account.flatMap { Self.projectURL(package, account: $0) })
                    .map(Self.withoutCredentials)
                result[key] = Self.metadata(of: package, repositoryURL: page)
                continue
            }
            guard let old = cached[key], let inHouse = old.inHouse else { continue }
            switch results[inHouse.accountId] {
            case .needsPermission(let reason)?:
                result[key] = PackageMetadata(latest: nil, versions: [:], inHouse: inHouse.with(status: .needsPermission(reason: reason)))
            case .failed?, nil:
                result[key] = old
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
