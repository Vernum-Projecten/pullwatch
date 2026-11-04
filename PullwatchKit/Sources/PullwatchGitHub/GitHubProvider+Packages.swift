import Foundation
public import PullwatchCore

/// Eén regel per account en per verzoek, op Info zodat `log show` ze ziet: dienst, manier van
/// inloggen, pad met de soort, status en aantal; bij een fout GitHubs `message`. Nooit een token
/// of een header.
private let logger = Log(category: "Packages")

/// De eigen packages in GitHub Packages: per gevolgde eigenaar en per soort één lijst
/// (`/orgs/{org}/packages` of `/users/{user}/packages`, 100 per pagina, `Link`-header voor de
/// volgende, alleen op de API van het account: `PageLink.follow`), gekoppeld aan de gevolgde repo's via `repository.full_name`. De recente versies
/// alleen voor packages van een gevolgde repo. Alleen in de dagelijkse versiecheck.
///
/// GitHub leest het register alleen met de scope `read:packages` (een `gh`-token of een persoonlijk
/// token (classic)). Een token van de GitHub App krijgt altijd 403 "Resource not accessible by
/// integration", ook met het recht Packages van de app (live gezien, #206); een GitHub App-account
/// leest de packages daarom met het token van de GitHub CLI (`packagesTokenSource`), nooit met zijn
/// eigen token. Een 401 of 403 is `.needsPermission` met de reden voor de manier van inloggen van
/// het account, nooit een mislukte check.
extension GitHubProvider {
    /// De soorten die de REST API van GitHub Packages kent (`package_type`, verplicht).
    static let packageTypes: [PublishedPackageType] = [.npm, .maven, .rubyGems, .docker, .nuGet, .container]

    /// Hoeveel versies per verzoek bij een package met echte versies (npm, Maven, NuGet).
    static let versionPageSize = 30
    /// Bij een image: pagina's van honderd, nieuwste eerst, tot er `recentVersionLimit` versies
    /// met een versietag zijn, hooguit `containerVersionPages`. Elke push naar main voegt images
    /// toe (commit-tags, handtekeningen, digests zonder tag), dus de release kan ouder zijn dan
    /// de nieuwste dertig of honderd.
    static let containerVersionPageSize = 100
    static let containerVersionPages = 5

    public func publishedPackages(followedRepos: [String]) async throws -> PublishedPackages {
        let host = endpoints.cliHost
        // Bij de GitHub App gaan de verzoeken aan het register met het token van `gh`; zonder
        // (uitgezet, niet geïnstalleerd, niet ingelogd) geen enkel verzoek.
        var tokens: (any TokenSource)?
        if authMethod == .gitHubApp {
            guard let packagesTokenSource else {
                logger.info("\(logPrefix): packages via gh staat uit, needsPermission")
                return .needsPermission(reason: GitHubPackagesReason.cliTurnedOff)
            }
            do {
                _ = try await packagesTokenSource.token()
            } catch ProviderError.cliNotFound {
                logger.info("\(logPrefix): gh niet gevonden, needsPermission")
                return .needsPermission(reason: GitHubPackagesReason.cliMissing(host: host))
            } catch ProviderError.cliNotLoggedIn {
                logger.info("\(logPrefix): gh niet ingelogd op \(host), needsPermission")
                return .needsPermission(reason: GitHubPackagesReason.cliLoggedOut(host: host))
            }
            tokens = packagesTokenSource
        }
        let followed = Dictionary(followedRepos.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var packages: [PublishedPackage] = []
        // Per eigenaar: een eigenaar waar het token niet bij het register mag, slaat alleen die
        // eigenaar over. Alleen als geen enkele eigenaar te lezen is, is het hele account
        // `.needsPermission`.
        var refusals: [PackagesAccess.Refusal] = []
        do {
            for owner in owners {
                do {
                    packages += try await ownerPackages(owner, followed: followed, tokens: tokens)
                } catch PackagesAccess.needsPermission(let refusal) {
                    refusals.append(refusal)
                    logger.info("\(logPrefix): geen recht op het register van \(owner), overgeslagen")
                }
            }
        } catch {
            logger.info("\(logPrefix): mislukt: \((error as? ProviderError)?.userMessage ?? error.localizedDescription)")
            throw error
        }
        if !owners.isEmpty, refusals.count == owners.count {
            logger.info("\(logPrefix): geen recht op het register, needsPermission")
            guard tokens != nil else { return .needsPermission(reason: GitHubPackagesReason.tokenMissesScope) }
            // Heeft `gh` de scope wel (GitHub noemt de scopes van een OAuth-token in
            // `X-OAuth-Scopes`), dan mag die gebruiker deze eigenaren niet zien.
            let lacksScope = refusals.contains { !$0.hasPackagesScope }
            return .needsPermission(
                reason: lacksScope ? GitHubPackagesReason.cliMissesScope(host: host) : GitHubPackagesReason.cliNoAccess(host: host)
            )
        }
        logger.info("\(logPrefix): \(packages.count) packages van \(owners.count - refusals.count) eigenaren, \(refusals.count) zonder recht")
        return .packages(packages)
    }

    /// De packages van één eigenaar (organisatie of gebruiker), alle soorten. Gooit
    /// `PackagesAccess.needsPermission` als het register van die eigenaar niet te lezen is.
    private func ownerPackages(
        _ owner: String, followed: [String: String], tokens: (any TokenSource)?
    ) async throws -> [PublishedPackage] {
        var packages: [PublishedPackage] = []
        let base = switch try await resolveOwnerKind(owner) {
        case .organization: apiBase.appending(path: "orgs").appending(path: owner)
        case .user: apiBase.appending(path: "users").appending(path: owner)
        }
        for type in Self.packageTypes {
            let listed: [PackageDTO] = try await packagePages(
                base.appending(path: "packages"),
                query: [
                    URLQueryItem(name: "package_type", value: type.rawValue),
                    URLQueryItem(name: "per_page", value: String(pageSize)),
                ],
                tokens: tokens
            )
            for item in listed {
                // Een package van een repo die niet gevolgd wordt, hoort niet in Pullwatch. Een
                // package zonder gekoppelde repo staat wel in de Packages-sectie, maar zonder versies
                // (die worden niet gevraagd), en is daarmee nooit een gecontroleerd eigen package (#215).
                let repo = item.repository.flatMap { followed[$0.fullName.lowercased()] }
                if item.repository != nil, repo == nil { continue }
                if type == .container {
                    let images = repo == nil ? [] : try await containerImages(of: item, type: type, base: base, tokens: tokens)
                    packages.append(item.package(
                        accountId: accountId, type: type, owner: owner, repository: repo, images: images ?? [], readFailed: images == nil
                    ))
                } else {
                    let versions = repo == nil ? [] : try await recentVersions(of: item, type: type, base: base, tokens: tokens)
                    packages.append(item.package(
                        accountId: accountId, type: type, owner: owner, repository: repo, versions: versions ?? [], readFailed: versions == nil
                    ))
                }
            }
        }
        return packages
    }

    /// "gitHub/gitHubApp account <id>" voor elke logregel.
    private var logPrefix: String {
        "\(ProviderKind.gitHub.rawValue)/\(authMethod.rawValue) account \(accountId.uuidString)"
    }

    /// Eén logregel voor een verzoek aan het register: pad met de soort (geen andere query), status,
    /// het aantal packages of versies, en bij een fout GitHubs `message`.
    private func logRequest(_ url: URL, type: String?, response: HTTPURLResponse, data: Data, count: Int?) {
        let path = url.path(percentEncoded: true) + (type.map { "?package_type=\($0)" } ?? "")
        let status = response.statusCode
        if (200..<300).contains(status) {
            logger.info("\(logPrefix): \(path) \(status), \(count ?? 0)")
        } else {
            struct Message: Decodable { let message: String? }
            let message = (try? JSONDecoder().decode(Message.self, from: data))?.message ?? ""
            logger.info("\(logPrefix): \(path) \(status) \(message)")
        }
    }

    /// De nieuwste versies van één package dat geen image is, nieuwste eerst. nil als het lezen
    /// mislukte (een 5xx, een time-out, een antwoord dat niet te lezen is): dat is een mislukking
    /// van dit package, gelogd, nooit een package dat geen versies heeft (#215). Een recht dat
    /// ontbreekt gaat door.
    private func recentVersions(
        of item: PackageDTO, type: PublishedPackageType, base: URL, tokens: (any TokenSource)?
    ) async throws -> [PublishedVersion]? {
        // `appending(component:)` codeert een "/" in de naam ("acme/web" als image) als %2F.
        let url = base.appending(path: "packages").appending(path: type.rawValue).appending(component: item.name).appending(path: "versions")
        do {
            let (data, response) = try await send(
                url, query: [URLQueryItem(name: "per_page", value: String(Self.versionPageSize))], checked: false,
                tokens: tokens
            )
            let items = (200..<300).contains(response.statusCode)
                ? try JSONDecoding.decode([PackageVersionDTO].self, from: data, snakeCase: true) : []
            logRequest(url, type: nil, response: response, data: data, count: items.count)
            guard try Self.checkPackagesAccess(response) else { return [] }
            try HTTPStatus.check(response, now: now())
            return Array(items.map(\.version).prefix(PublishedPackage.recentVersionLimit))
        } catch let refused as PackagesAccess {
            throw refused
        } catch {
            logReadFailure(url, error: error)
            return nil
        }
    }

    /// Eén logregel voor versies die niet te lezen waren: het pad en de fout, nooit een token.
    private func logReadFailure(_ url: URL, error: any Error) {
        let message = (error as? ProviderError)?.userMessage ?? error.localizedDescription
        logger.error("\(logPrefix): \(url.path(percentEncoded: true)) versies niet te lezen: \(message)")
    }

    /// De images van een container-package met hun tags, nieuwste eerst: pagina's van honderd tot
    /// er genoeg versietags zijn (`containerVersionPages`). Een fout op de eerste pagina (behalve
    /// een recht dat ontbreekt) is nil, een mislukking van dit package (#215); op een latere
    /// pagina blijft wat al gelezen is.
    private func containerImages(
        of item: PackageDTO, type: PublishedPackageType, base: URL, tokens: (any TokenSource)?
    ) async throws -> [ContainerVersions.Image]? {
        let url = base.appending(path: "packages").appending(path: type.rawValue).appending(component: item.name).appending(path: "versions")
        var images: [ContainerVersions.Image] = []
        var next: (url: URL, query: [URLQueryItem])? = (url, [URLQueryItem(name: "per_page", value: String(Self.containerVersionPageSize))])
        var pages = 0
        while let current = next, pages < Self.containerVersionPages {
            do {
                let (data, response) = try await send(current.url, query: current.query, checked: false, tokens: tokens)
                let items = (200..<300).contains(response.statusCode)
                    ? try JSONDecoding.decode([PackageVersionDTO].self, from: data, snakeCase: true) : []
                logRequest(current.url, type: nil, response: response, data: data, count: items.count)
                guard try Self.checkPackagesAccess(response) else { break }
                try HTTPStatus.check(response, now: now())
                images += items.map(\.image)
                next = PageLink.follow(Self.nextLink(response), after: current.url, api: apiBase).map { ($0, []) }
            } catch let refused as PackagesAccess {
                throw refused
            } catch {
                logReadFailure(current.url, error: error)
                if pages == 0 { return nil }
                break
            }
            pages += 1
            if ContainerVersions.versionTaggedCount(images) >= PublishedPackage.recentVersionLimit { break }
        }
        return images
    }

    /// Alle pagina's van een lijst van packages, via de `next`-link, hooguit `maxPages`. Een 404
    /// (geen packages, of een server zonder dit register) en een 400 of 422 (een soort die de
    /// server niet kent) zijn een lege lijst.
    private func packagePages(_ url: URL, query: [URLQueryItem], tokens: (any TokenSource)?) async throws -> [PackageDTO] {
        var items: [PackageDTO] = []
        var next: (url: URL, query: [URLQueryItem])? = (url, query)
        var pages = 0
        while let current = next, pages < maxPages {
            let (data, response) = try await send(current.url, query: current.query, checked: false, tokens: tokens)
            let page = (200..<300).contains(response.statusCode)
                ? try JSONDecoding.decode([PackageDTO].self, from: data, snakeCase: true) : []
            let type = (current.query + (URLComponents(url: current.url, resolvingAgainstBaseURL: false)?.queryItems ?? []))
                .first { $0.name == "package_type" }?.value
            logRequest(current.url, type: type, response: response, data: data, count: page.count)
            guard try Self.checkPackagesAccess(response) else { break }
            try HTTPStatus.check(response, now: now())
            items += page
            next = PageLink.follow(Self.nextLink(response), after: current.url, api: apiBase).map { ($0, []) }
            pages += 1
        }
        return items
    }

    /// false: niets te lezen (404, 400, 422). Gooit `needsPermission` bij 401 en bij een 403 die
    /// geen rate limit is, met de scopes uit `X-OAuth-Scopes`; de rest gaat naar `HTTPStatus.check`.
    static func checkPackagesAccess(_ response: HTTPURLResponse) throws -> Bool {
        let refusal = PackagesAccess.Refusal(scopesHeader: response.value(forHTTPHeaderField: "X-OAuth-Scopes"))
        switch response.statusCode {
        case 401:
            throw PackagesAccess.needsPermission(refusal)
        case 403:
            let rateLimited = response.value(forHTTPHeaderField: "Retry-After") != nil
                || response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
            if rateLimited { return true }
            throw PackagesAccess.needsPermission(refusal)
        case 400, 404, 422:
            return false
        default:
            return true
        }
    }
}

enum PackagesAccess: Error {
    /// Een weigering, met wat GitHub over de scopes van het token zei.
    struct Refusal {
        /// De scopes uit `X-OAuth-Scopes`; nil als GitHub de header niet stuurde (een token van
        /// een GitHub App of een fine-grained token).
        let scopes: Set<String>?

        init(scopesHeader: String?) {
            scopes = scopesHeader.map { header in
                Set(header.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            }
        }

        /// Of het token de packages mag lezen: `read:packages`, of `write:packages`, dat lezen
        /// insluit. Zonder header onbekend, en dan geldt de scope als ontbrekend.
        var hasPackagesScope: Bool {
            guard let scopes else { return false }
            return scopes.contains("read:packages") || scopes.contains("write:packages")
        }
    }

    case needsPermission(Refusal)
}

// MARK: - DTO's

private struct PackageDTO: Decodable {
    struct Repository: Decodable {
        let fullName: String
    }

    let name: String
    let visibility: String?
    let htmlUrl: String?
    let updatedAt: String?
    let repository: Repository?

    /// Een container-package: de versies uit de tags van zijn images.
    func package(
        accountId: UUID, type: PublishedPackageType, owner: String, repository: String?, images: [ContainerVersions.Image],
        readFailed: Bool
    ) -> PublishedPackage {
        PublishedPackage(
            accountId: accountId, name: name, type: type, owner: owner, repository: repository,
            container: ContainerVersions(images: images), fallbackDate: updatedAt.flatMap(DateParsing.parse),
            visibility: visibility.flatMap(PublishedPackage.Visibility.init(rawValue:)), webURL: htmlUrl.flatMap(URL.init(string:)),
            versionsReadFailed: readFailed
        )
    }

    func package(
        accountId: UUID, type: PublishedPackageType, owner: String, repository: String?, versions: [PublishedVersion], readFailed: Bool
    ) -> PublishedPackage {
        PublishedPackage(
            accountId: accountId, name: name, type: type, owner: owner, repository: repository,
            publishedAt: versions.first?.publishedAt ?? updatedAt.flatMap(DateParsing.parse),
            visibility: visibility.flatMap(PublishedPackage.Visibility.init(rawValue:)),
            webURL: htmlUrl.flatMap(URL.init(string:)), versions: versions, versionsReadFailed: readFailed
        )
    }
}

private struct PackageVersionDTO: Decodable {
    struct Metadata: Decodable {
        struct Container: Decodable {
            let tags: [String]?
        }
        let container: Container?
    }

    let name: String
    let createdAt: String?
    let htmlUrl: String?
    let metadata: Metadata?

    /// De versie zoals het register hem noemt (npm, Maven, NuGet, RubyGems).
    var version: PublishedVersion {
        PublishedVersion(version: name, publishedAt: createdAt.flatMap(DateParsing.parse), webURL: htmlUrl.flatMap(URL.init(string:)))
    }

    /// Bij een image is de naam een digest; de tags staan in de metadata (`ContainerVersions`).
    var image: ContainerVersions.Image {
        ContainerVersions.Image(
            tags: metadata?.container?.tags ?? [], publishedAt: createdAt.flatMap(DateParsing.parse), webURL: htmlUrl.flatMap(URL.init(string:))
        )
    }
}
