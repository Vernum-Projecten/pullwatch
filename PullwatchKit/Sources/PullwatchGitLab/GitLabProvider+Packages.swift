import Foundation
public import PullwatchCore

/// Eén regel per account en per verzoek, op Info zodat `log show` ze ziet: dienst, account, pad,
/// status en aantal; bij een fout GitLabs `message` of `error`. Nooit een token of een header.
private let logger = Log(category: "Packages")

/// De eigen packages in GitLab: het pakketregister (npm, Maven, NuGet, PyPI, Composer, Conan, Helm,
/// Go, generic, Terraform) en de container registry, van de gevolgde projecten. Alleen in de
/// dagelijkse versiecheck.
///
/// GitLab geeft elke versie als een eigen package-regel. Per gevolgde groep gaat er één lijst
/// (`/groups/:id/packages`, met subgroepen, nieuwste eerst) en één lijst van images
/// (`/groups/:id/registry/repositories`): dat is één vraag per groep in plaats van één per
/// project. Was de lijst van een groep langer dan `groupPackagePages`, dan krijgen de gevolgde
/// projecten daarin die geen regel kregen alsnog hun eigen lijst, zodat een project met alleen
/// oude packages niet wegvalt. Projecten van een gebruiker en losse projecten
/// (`Account.extraRepos`, ook zonder token als ze zo gelezen worden) krijgen per project één lijst
/// (`/projects/:id/packages`, `/projects/:id/registry/repositories`).
///
/// Van een image de tien nieuwste tags in één vraag (keyset, `order_by=published_at`), en alleen
/// van de nieuwste de details voor zijn datum. Een server zonder de metadata-database van de
/// registry kent die sortering niet; dan één pagina tags en de details van hooguit tien.
///
/// Het token leest dit met de scope `read_api`. Een 401, of een 403 met `insufficient_scope`, is
/// daarom `.needsPermission`, nooit een mislukte check. Een gewone 403 op één project (register
/// uit, of geen lid) laat dat project leeg; op een groep is het `.needsPermission`. Een 404 is
/// een leeg register.
extension GitLabProvider {
    /// Pagina's van honderd regels per gevolgde groep, nieuwste eerst.
    static let groupPackagePages = 5
    /// Pagina's van honderd regels per project.
    static let projectPackagePages = 3
    /// Pagina's van honderd images per groep of project.
    static let registryPages = 2

    public func publishedPackages(followedRepos: [String]) async throws -> PublishedPackages {
        let followed = Dictionary(followedRepos.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var rows: [(repo: String, row: PackageRowDTO)] = []
        var images: [(repo: String, image: RegistryRepositoryDTO, anonymous: Bool)] = []
        do {
            // Wat nog een eigen lijst per project nodig heeft (lowercased).
            var packagesLeft = Set(followed.keys)
            var imagesLeft = Set(followed.keys)
            for owner in owners {
                guard case .group(let path) = try await resolve(owner) else { continue }
                let members = Set(followed.keys.filter { $0.hasPrefix(path.lowercased() + "/") })
                guard !members.isEmpty else { continue }

                if let listed: Listing<PackageRowDTO> = try await listing(
                    endpoint("groups", path, "packages"), query: Self.packageQuery, maxPages: Self.groupPackagePages,
                    anonymous: false, inProject: false
                ) {
                    let found = listed.items.compactMap { row in
                        row.projectPath.flatMap { followed[$0.lowercased()] }.map { (repo: $0, row: row) }
                    }
                    rows += found
                    packagesLeft.subtract(listed.complete ? members : Set(found.map { $0.repo.lowercased() }))
                }

                if let listed: Listing<RegistryRepositoryDTO> = try await listing(
                    endpoint("groups", path, "registry", "repositories"), query: [], maxPages: Self.registryPages,
                    anonymous: false, inProject: false
                ) {
                    let found = listed.items.compactMap { image in
                        Self.project(of: image, in: members).flatMap { followed[$0] }.map { (repo: $0, image: image, anonymous: false) }
                    }
                    images += found
                    imagesLeft.subtract(listed.complete ? members : Set(found.map { $0.repo.lowercased() }))
                }
            }

            for key in packagesLeft.union(imagesLeft).sorted() {
                guard let repo = followed[key] else { continue }
                let anonymous: Bool
                do {
                    anonymous = try await readsAnonymously(repo)
                } catch {
                    continue // een los project dat er niet (meer) is, of de limiet zonder token is op
                }
                do {
                    if packagesLeft.contains(key), let listed: Listing<PackageRowDTO> = try await listing(
                        endpoint("projects", repo, "packages"), query: Self.packageQuery, maxPages: Self.projectPackagePages,
                        anonymous: anonymous, inProject: true
                    ) {
                        rows += listed.items.map { (repo: repo, row: $0) }
                    }
                    if imagesLeft.contains(key), let listed: Listing<RegistryRepositoryDTO> = try await listing(
                        endpoint("projects", repo, "registry", "repositories"), query: [], maxPages: Self.registryPages,
                        anonymous: anonymous, inProject: true
                    ) {
                        images += listed.items.map { (repo: repo, image: $0, anonymous: anonymous) }
                    }
                } catch ProviderError.rateLimited(let until) where anonymous {
                    anonymousPausedUntil = until
                }
            }

            var packages = Self.packages(from: rows, accountId: accountId, instanceURL: instanceURL)
            for image in images {
                let versions = try await recentTags(of: image.image, in: image.repo, anonymous: image.anonymous)
                packages.append(PublishedPackage(
                    accountId: accountId, name: image.image.path, type: .container, owner: Self.namespace(of: image.repo),
                    repository: image.repo, webURL: webURL(image.repo, "container_registry", String(image.image.id)),
                    versions: versions
                ))
            }
            logger.info("\(logPrefix): \(packages.count) packages van \(followedRepos.count) gevolgde projecten")
            return .packages(packages)
        } catch PackagesDenied.needsPermission {
            logger.info("\(logPrefix): geen recht op het register, needsPermission")
            return .needsPermission(reason: PackagesPermission.gitLabReadAPI)
        } catch {
            logger.info("\(logPrefix): mislukt: \((error as? ProviderError)?.userMessage ?? error.localizedDescription)")
            throw error
        }
    }

    /// Nieuwste eerst, en alleen wat te gebruiken is (geen package dat nog verwerkt wordt of kapot is).
    private static let packageQuery = [
        URLQueryItem(name: "order_by", value: "created_at"),
        URLQueryItem(name: "sort", value: "desc"),
    ]

    /// Eén package per project, soort en naam, met zijn recente versies nieuwste eerst.
    private static func packages(
        from rows: [(repo: String, row: PackageRowDTO)], accountId: UUID, instanceURL: URL
    ) -> [PublishedPackage] {
        var order: [String] = []
        var grouped: [String: [(repo: String, row: PackageRowDTO)]] = [:]
        for item in rows where item.row.isUsable {
            let key = "\(item.repo.lowercased())\n\(item.row.packageType.lowercased())\n\(item.row.name)"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(item)
        }
        return order.compactMap { key in
            guard let items = grouped[key], let first = items.first else { return nil }
            let sorted = items.sorted { ($0.row.created ?? .distantPast) > ($1.row.created ?? .distantPast) }
            let versions = sorted.prefix(PublishedPackage.recentVersionLimit).map { $0.row.version(instanceURL: instanceURL) }
            return PublishedPackage(
                accountId: accountId, name: first.row.name, type: PublishedPackageType(rawValue: first.row.packageType),
                owner: namespace(of: first.repo), repository: first.repo, webURL: versions.first?.webURL, versions: Array(versions)
            )
        }
    }

    /// De groep of gebruiker van een project: "acme/platform" voor "acme/platform/api".
    static func namespace(of repo: String) -> String {
        guard let slash = repo.lastIndex(of: "/") else { return repo }
        return String(repo[..<slash])
    }

    /// Het gevolgde project (lowercased) van een image uit de lijst van een groep: het langste
    /// project waarvan het pad van de image het pad is of mee begint ("acme/web" of "acme/web/api").
    static func project(of image: RegistryRepositoryDTO, in members: Set<String>) -> String? {
        let path = image.path.lowercased()
        return members.filter { path == $0 || path.hasPrefix($0 + "/") }.max { $0.count < $1.count }
    }

    // MARK: - Tags van een image

    /// De nieuwste tags van een image, nieuwste eerst, hooguit `recentVersionLimit`; "latest" alleen
    /// als er niets anders is. Een fout hier (behalve een recht dat ontbreekt) laat de image zonder
    /// versies staan.
    private func recentTags(of image: RegistryRepositoryDTO, in repo: String, anonymous: Bool) async throws -> [PublishedVersion] {
        let tagsURL = endpoint("projects", repo, "registry", "repositories", String(image.id), "tags")
        let limit = PublishedPackage.recentVersionLimit
        do {
            let (data, response) = try await send(tagsURL, query: [
                URLQueryItem(name: "pagination", value: "keyset"),
                URLQueryItem(name: "order_by", value: "published_at"),
                URLQueryItem(name: "sort", value: "desc"),
                URLQueryItem(name: "per_page", value: String(limit + 1)),
            ], anonymous: anonymous, checked: false)
            let newest = (200..<300).contains(response.statusCode)
                ? try JSONDecoding.decode([ContainerTagDTO].self, from: data, snakeCase: true) : []
            logRequest(tagsURL, response: response, data: data, count: newest.count)
            if try Self.packagesAccess(response, data: data, anonymous: anonymous, inProject: true) {
                try HTTPStatus.check(response, now: now())
                let names = Self.withoutLatest(newest.map(\.name)).prefix(limit)
                guard let first = names.first else { return [] }
                // Alleen van de nieuwste de datum: één verzoek per image.
                let created = try await tagDetail(first, tagsURL: tagsURL, anonymous: anonymous)?.created
                let link = webURL(repo, "container_registry", String(image.id))
                return names.enumerated().map { index, name in
                    PublishedVersion(version: name, publishedAt: index == 0 ? created : nil, webURL: link)
                }
            }
            return try await recentTagsByDetail(tagsURL: tagsURL, image: image, repo: repo, anonymous: anonymous)
        } catch PackagesDenied.needsPermission {
            throw PackagesDenied.needsPermission
        } catch {
            return []
        }
    }

    /// Zonder sortering op datum (een server zonder de metadata-database): één pagina tags, de
    /// hoogste tien op naam (numeriek), en hun details om op datum te sorteren.
    private func recentTagsByDetail(
        tagsURL: URL, image: RegistryRepositoryDTO, repo: String, anonymous: Bool
    ) async throws -> [PublishedVersion] {
        let (data, response) = try await send(tagsURL, query: [URLQueryItem(name: "per_page", value: String(pageSize))], anonymous: anonymous, checked: false)
        let tags = (200..<300).contains(response.statusCode)
            ? try JSONDecoding.decode([ContainerTagDTO].self, from: data, snakeCase: true) : []
        logRequest(tagsURL, response: response, data: data, count: tags.count)
        guard try Self.packagesAccess(response, data: data, anonymous: anonymous, inProject: true) else { return [] }
        try HTTPStatus.check(response, now: now())
        let candidates = Self.withoutLatest(tags.map(\.name))
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .prefix(PublishedPackage.recentVersionLimit)
        var detailed: [(name: String, created: Date?)] = []
        for name in candidates {
            detailed.append((name, try await tagDetail(name, tagsURL: tagsURL, anonymous: anonymous)?.created))
        }
        let link = webURL(repo, "container_registry", String(image.id))
        return detailed
            .sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
            .map { PublishedVersion(version: $0.name, publishedAt: $0.created, webURL: link) }
    }

    /// De details van één tag (`created_at`); nil als die niet te lezen zijn.
    private func tagDetail(_ name: String, tagsURL: URL, anonymous: Bool) async throws -> ContainerTagDTO? {
        let url = URL(string: tagsURL.absoluteString + "/" + Self.encode(name))!
        let (data, response) = try await send(url, anonymous: anonymous, checked: false)
        let tag = (200..<300).contains(response.statusCode) ? try? JSONDecoding.decode(ContainerTagDTO.self, from: data, snakeCase: true) : nil
        logRequest(url, response: response, data: data, count: tag == nil ? 0 : 1)
        guard try Self.packagesAccess(response, data: data, anonymous: anonymous, inProject: true) else { return nil }
        try HTTPStatus.check(response, now: now())
        return tag
    }

    /// "latest" zegt niets over de versie; alleen als er geen andere tag is, blijft hij staan.
    static func withoutLatest(_ names: [String]) -> [String] {
        let others = names.filter { $0 != "latest" }
        return others.isEmpty ? names : others
    }

    // MARK: - Lijsten

    /// De regels van een lijst en of alle pagina's gelezen zijn.
    struct Listing<Item> {
        var items: [Item]
        var complete: Bool
    }

    /// Alle pagina's van een lijst, hooguit `maxPages` van `pageSize`, via `x-next-page` of de
    /// `Link`-header. nil als er niets te lezen is (404, of een project dat het register niet laat
    /// zien); gooit `needsPermission` als het token het recht mist.
    private func listing<Item: Decodable>(
        _ url: URL, query: [URLQueryItem], maxPages: Int, anonymous: Bool, inProject: Bool
    ) async throws -> Listing<Item>? {
        var items: [Item] = []
        var next: URL? = Self.withQuery(url, query + [
            URLQueryItem(name: "per_page", value: String(pageSize)),
            URLQueryItem(name: "page", value: "1"),
        ])
        var fetched = 0
        while let current = next {
            guard fetched < maxPages else { return Listing(items: items, complete: false) }
            let (data, response) = try await send(current, anonymous: anonymous, checked: false)
            let page = (200..<300).contains(response.statusCode)
                ? try JSONDecoding.decode([Item].self, from: data, snakeCase: true) : []
            logRequest(current, response: response, data: data, count: page.count)
            guard try Self.packagesAccess(response, data: data, anonymous: anonymous, inProject: inProject) else {
                return fetched == 0 ? nil : Listing(items: items, complete: false)
            }
            try HTTPStatus.check(response, now: now())
            items += page
            fetched += 1
            next = nextPage(after: current, response: response, base: url, query: query)
        }
        return Listing(items: items, complete: true)
    }

    /// false: niets te lezen. Gooit `needsPermission` bij een 401 met token, bij een 403 met
    /// `insufficient_scope` en bij een gewone 403 op een groep; een gewone 403 op een project en
    /// alles zonder token is niets te lezen. Een rate limit gaat door naar `HTTPStatus.check`.
    static func packagesAccess(_ response: HTTPURLResponse, data: Data, anonymous: Bool, inProject: Bool) throws -> Bool {
        switch response.statusCode {
        case 401:
            if anonymous { return false }
            throw PackagesDenied.needsPermission
        case 403:
            let rateLimited = response.value(forHTTPHeaderField: "Retry-After") != nil
                || response.value(forHTTPHeaderField: "RateLimit-Remaining") == "0"
            if rateLimited { return true }
            if anonymous { return false }
            struct Denial: Decodable { let error: String? }
            let insufficientScope = (try? JSONDecoder().decode(Denial.self, from: data))?.error == "insufficient_scope"
            if inProject, !insufficientScope { return false }
            throw PackagesDenied.needsPermission
        case 400, 404, 422:
            return false
        default:
            return true
        }
    }

    // MARK: - Loggen

    /// "gitLab account <id>" voor elke logregel.
    private var logPrefix: String {
        "\(ProviderKind.gitLab.rawValue) account \(accountId.uuidString)"
    }

    /// Eén logregel voor een verzoek: het pad zonder query, status, het aantal regels, en bij een
    /// fout GitLabs `message` of `error`.
    private func logRequest(_ url: URL, response: HTTPURLResponse, data: Data, count: Int) {
        let path = url.path(percentEncoded: true)
        let status = response.statusCode
        if (200..<300).contains(status) {
            logger.info("\(logPrefix): \(path) \(status), \(count)")
        } else {
            struct Message: Decodable {
                let message: String?
                let error: String?
            }
            let decoded = try? JSONDecoder().decode(Message.self, from: data)
            logger.info("\(logPrefix): \(path) \(status) \(decoded?.message ?? decoded?.error ?? "")")
        }
    }
}

private enum PackagesDenied: Error {
    case needsPermission
}

// MARK: - DTO's

/// Eén versie van een package in de lijst van een project of groep.
struct PackageRowDTO: Decodable {
    struct Links: Decodable {
        let webPath: String?
    }

    struct Pipeline: Decodable {
        let ref: String?
        let tag: Bool?
        let webUrl: String?
    }

    let name: String
    let version: String?
    let packageType: String
    let status: String?
    let createdAt: String?
    let projectPath: String?
    let links: Links?
    let pipeline: Pipeline?
    /// Verouderd sinds GitLab 16.1, maar oudere servers vullen alleen dit.
    let pipelines: [Pipeline]?

    private enum CodingKeys: String, CodingKey {
        case name, version, packageType, status, createdAt, projectPath, pipeline, pipelines
        case links = "_links"
    }

    var created: Date? { createdAt.flatMap(DateParsing.parse) }

    /// Een versie die te gebruiken is: met een versie, en niet nog in verwerking of kapot.
    var isUsable: Bool {
        guard let version, !version.isEmpty else { return false }
        return status == nil || status == "default" || status == "deprecated"
    }

    func version(instanceURL: URL) -> PublishedVersion {
        let version = version ?? ""
        let run = pipeline ?? pipelines?.first
        // De ref is alleen een tag als GitLab dat zegt, of als hij de versie zelf noemt ("v2.3.0").
        let tag = run?.ref.flatMap { ref in
            run?.tag == true || ref == version || ref == "v" + version ? ref : nil
        }
        return PublishedVersion(
            version: version, publishedAt: created,
            // Een pad op de server, net als een foto: `avatarURL` zet het niet dubbel achter `/gitlab`.
            webURL: GitLabProvider.avatarURL(links?.webPath, instanceURL: instanceURL),
            tag: tag, runURL: run?.webUrl.flatMap(URL.init(string:))
        )
    }
}

/// Een image in de container registry van een project.
struct RegistryRepositoryDTO: Decodable {
    let id: Int
    /// "groep/project" of "groep/project/naam".
    let path: String
}

/// Een tag van een image; `created_at` alleen in de details van één tag.
struct ContainerTagDTO: Decodable {
    let name: String
    let createdAt: String?

    var created: Date? { createdAt.flatMap(DateParsing.parse) }
}
