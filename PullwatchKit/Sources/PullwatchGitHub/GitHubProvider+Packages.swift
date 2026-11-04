import Foundation
public import PullwatchCore

/// Eén regel per account en per verzoek, op Info zodat `log show` ze ziet: dienst, manier van
/// inloggen, pad met de soort, status en aantal; bij een fout GitHubs `message`. Nooit een token
/// of een header.
private let logger = Log(category: "Packages")

/// De eigen packages in GitHub Packages: per gevolgde eigenaar en per soort één lijst
/// (`/orgs/{org}/packages` of `/users/{user}/packages`, 100 per pagina, `Link`-header voor de
/// volgende), gekoppeld aan de gevolgde repo's via `repository.full_name`. De recente versies
/// alleen voor packages van een gevolgde repo. Alleen in de dagelijkse versiecheck.
///
/// GitHub leest het register met de scope `read:packages` (een `gh`-token of een persoonlijk token
/// (classic)) of, bij de GitHub App, met het repository-recht Packages (lezen), dat optioneel is
/// (docs/github-app.md). Een 401 of 403 is daarom `.needsPermission` met de reden voor de manier
/// van inloggen van het account, nooit een mislukte check.
extension GitHubProvider {
    /// De soorten die de REST API van GitHub Packages kent (`package_type`, verplicht).
    static let packageTypes: [PublishedPackageType] = [.npm, .maven, .rubyGems, .docker, .nuGet, .container]

    /// Hoeveel versies per verzoek: images hebben ook versies zonder tag (tussenlagen, oude
    /// digests), dus ruim genoeg om er `PublishedPackage.recentVersionLimit` met tag over te houden.
    static let versionPageSize = 30

    /// Wat er nodig is als GitHub het register weigert, per manier van inloggen: bij de GitHub App
    /// het recht Packages van de app (de eigenaar van de app zet het aan, elke installatie keurt
    /// het goed, docs/github-app.md sectie 6), anders de scope `read:packages` van het token.
    static func packagesPermissionReason(for authMethod: AuthMethod) -> String {
        switch authMethod {
        case .gitHubApp:
            String(
                localized: "Pullwatch heeft het recht Packages (lezen) op zijn GitHub App nodig: de eigenaar van de app zet het aan, daarna keur je het nieuwe recht goed (docs/github-app.md).",
                bundle: .localizedGitHub,
                comment: "Reden waarom de packages van een GitHub-account via de GitHub App niet te lezen zijn; Packages is de naam van het recht bij GitHub"
            )
        case .pat, .cli:
            String(
                localized: "GitHub Packages is alleen te lezen met de scope read:packages: gebruik de GitHub CLI (gh auth refresh -s read:packages) of een persoonlijk token (classic) met read:packages.",
                bundle: .localizedGitHub,
                comment: "Reden waarom de packages van een GitHub-account met de GitHub CLI of een token niet te lezen zijn; read:packages en de gh-opdracht niet vertalen"
            )
        }
    }

    public func publishedPackages(followedRepos: [String]) async throws -> PublishedPackages {
        let followed = Dictionary(followedRepos.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var packages: [PublishedPackage] = []
        do {
            for owner in owners {
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
                        ]
                    )
                    for item in listed {
                        // Een package van een repo die niet gevolgd wordt, hoort niet in Pullwatch.
                        let repo = item.repository.flatMap { followed[$0.fullName.lowercased()] }
                        if item.repository != nil, repo == nil { continue }
                        let versions = repo == nil ? [] : try await recentVersions(of: item, type: type, base: base)
                        packages.append(item.package(accountId: accountId, type: type, owner: owner, repository: repo, versions: versions))
                    }
                }
            }
        } catch PackagesAccess.needsPermission {
            logger.info("\(logPrefix): geen recht op het register, needsPermission")
            return .needsPermission(reason: Self.packagesPermissionReason(for: authMethod))
        } catch {
            logger.info("\(logPrefix): mislukt: \((error as? ProviderError)?.userMessage ?? error.localizedDescription)")
            throw error
        }
        logger.info("\(logPrefix): \(packages.count) packages van \(owners.count) eigenaren")
        return .packages(packages)
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

    /// De nieuwste versies van één package, nieuwste eerst; een image zonder tag telt niet. Een
    /// fout hier (behalve een recht dat ontbreekt) laat het package zonder versies staan.
    private func recentVersions(of item: PackageDTO, type: PublishedPackageType, base: URL) async throws -> [PublishedVersion] {
        // `appending(component:)` codeert een "/" in de naam ("acme/web" als image) als %2F.
        let url = base.appending(path: "packages").appending(path: type.rawValue).appending(component: item.name).appending(path: "versions")
        do {
            let (data, response) = try await send(
                url, query: [URLQueryItem(name: "per_page", value: String(Self.versionPageSize))], checked: false
            )
            let items = (200..<300).contains(response.statusCode)
                ? try JSONDecoding.decode([PackageVersionDTO].self, from: data, snakeCase: true) : []
            logRequest(url, type: nil, response: response, data: data, count: items.count)
            guard try Self.checkPackagesAccess(response) else { return [] }
            try HTTPStatus.check(response, now: now())
            return Array(items.compactMap { $0.version(type: type) }.prefix(PublishedPackage.recentVersionLimit))
        } catch PackagesAccess.needsPermission {
            throw PackagesAccess.needsPermission
        } catch {
            return []
        }
    }

    /// Alle pagina's van een lijst van packages, via de `next`-link, hooguit `maxPages`. Een 404
    /// (geen packages, of een server zonder dit register) en een 400 of 422 (een soort die de
    /// server niet kent) zijn een lege lijst.
    private func packagePages(_ url: URL, query: [URLQueryItem]) async throws -> [PackageDTO] {
        var items: [PackageDTO] = []
        var next: (url: URL, query: [URLQueryItem])? = (url, query)
        var pages = 0
        while let current = next, pages < maxPages {
            let (data, response) = try await send(current.url, query: current.query, checked: false)
            let page = (200..<300).contains(response.statusCode)
                ? try JSONDecoding.decode([PackageDTO].self, from: data, snakeCase: true) : []
            let type = (current.query + (URLComponents(url: current.url, resolvingAgainstBaseURL: false)?.queryItems ?? []))
                .first { $0.name == "package_type" }?.value
            logRequest(current.url, type: type, response: response, data: data, count: page.count)
            guard try Self.checkPackagesAccess(response) else { break }
            try HTTPStatus.check(response, now: now())
            items += page
            next = Self.nextLink(response).map { ($0, []) }
            pages += 1
        }
        return items
    }

    /// false: niets te lezen (404, 400, 422). Gooit `needsPermission` bij 401 en bij een 403 die
    /// geen rate limit is; de rest gaat naar `HTTPStatus.check`.
    static func checkPackagesAccess(_ response: HTTPURLResponse) throws -> Bool {
        switch response.statusCode {
        case 401:
            throw PackagesAccess.needsPermission
        case 403:
            let rateLimited = response.value(forHTTPHeaderField: "Retry-After") != nil
                || response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
            if rateLimited { return true }
            throw PackagesAccess.needsPermission
        case 400, 404, 422:
            return false
        default:
            return true
        }
    }
}

enum PackagesAccess: Error {
    case needsPermission
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

    func package(
        accountId: UUID, type: PublishedPackageType, owner: String, repository: String?, versions: [PublishedVersion]
    ) -> PublishedPackage {
        PublishedPackage(
            accountId: accountId, name: name, type: type, owner: owner, repository: repository,
            publishedAt: versions.first?.publishedAt ?? updatedAt.flatMap(DateParsing.parse),
            visibility: visibility.flatMap(PublishedPackage.Visibility.init(rawValue:)),
            webURL: htmlUrl.flatMap(URL.init(string:)), versions: versions
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

    /// De versie zoals een mens hem noemt: bij een image de eerste tag naast "latest" (de naam is
    /// daar een digest), anders de naam. Een image zonder tag geeft nil.
    func version(type: PublishedPackageType) -> PublishedVersion? {
        let label: String
        if type == .container {
            let tags = metadata?.container?.tags ?? []
            guard let tag = tags.first(where: { $0 != "latest" }) ?? tags.first else { return nil }
            label = tag
        } else {
            label = name
        }
        return PublishedVersion(
            version: label, publishedAt: createdAt.flatMap(DateParsing.parse), webURL: htmlUrl.flatMap(URL.init(string:))
        )
    }
}
