import Foundation
public import PullwatchCore

/// Eén regel per account en per verzoek, op Info zodat `log show` ze ziet: dienst en manier van
/// inloggen, account, pad, status en aantal; bij een fout de `message` van Azure DevOps. Nooit een
/// token of een header.
private let logger = Log(category: "Packages")

/// De eigen packages in Azure Artifacts: de feeds van de organisatie en van de projecten met
/// gevolgde repo's (`feeds.dev.azure.com/{org}[/{project}]/_apis/packaging/feeds`), en per feed de
/// packages met hun nieuwste versie (`…/Feeds/{id}/packages`, 100 per pagina met `$top` en
/// `$skip`). Een feed hoort bij geen repository: `repository` blijft nil en het package staat onder
/// zijn project (`owner`), of onder de organisatie bij een feed van de organisatie. Een package dat
/// de feed uit een upstream (npmjs.com, nuget.org) bewaarde, is niet van jou en valt weg. Alleen
/// in de dagelijkse versiecheck.
///
/// Azure noemt de hoogste versie `isLatest`, ook een pre-release. Is die versie een pre-release,
/// dan volgen de versies van dat package (`…/Packages/{id}/versions`), zodat de hoogste stabiele
/// release de nieuwste versie is en de pre-release alleen genoemd wordt, zoals bij een image (#219).
///
/// Een PAT leest dit met het recht Packaging (Read); het token van `az` kan het als het account de
/// feeds mag lezen. Een 401 of 403 is daarom `.needsPermission`, nooit een mislukte check; een 404
/// (geen Azure Artifacts, of een feed die weg is) is leeg.
extension AzureDevOpsProvider {
    /// Hooguit zoveel pagina's van `pageSize` packages per feed.
    static let feedPackagePages = 10

    var feedsBaseURL: URL {
        URL(string: "https://feeds.dev.azure.com")!.appending(path: organization)
    }

    public func publishedPackages(followedRepos: [String]) async throws -> PublishedPackages {
        // De projecten met gevolgde repo's ("project/repo"), elk één keer.
        var projects: [String] = []
        for repo in followedRepos {
            guard let slash = repo.firstIndex(of: "/") else { continue }
            let project = String(repo[..<slash])
            if !projects.contains(where: { $0.caseInsensitiveCompare(project) == .orderedSame }) { projects.append(project) }
        }
        let followedProjects = Set(projects.map { $0.lowercased() })
        do {
            var feeds: [FeedDTO] = []
            var seen: Set<String> = []
            for base in [feedsBaseURL] + projects.map({ feedsBaseURL.appending(path: $0) }) {
                for feed in try await feedList(base) where seen.insert(feed.id).inserted {
                    // Een feed van een project zonder gevolgde repo hoort niet in Pullwatch.
                    if let project = feed.project?.name, !followedProjects.contains(project.lowercased()) { continue }
                    if feed.deletedDate != nil { continue }
                    feeds.append(feed)
                }
            }
            var byId: [String: PublishedPackage] = [:]
            var order: [String] = []
            for feed in feeds {
                for package in try await packages(in: feed) {
                    // Hetzelfde package in twee feeds van één project: de nieuwste telt.
                    if let known = byId[package.id], (known.publishedAt ?? .distantPast) >= (package.publishedAt ?? .distantPast) { continue }
                    if byId[package.id] == nil { order.append(package.id) }
                    byId[package.id] = package
                }
            }
            let packages = order.compactMap { byId[$0] }
            logger.info("\(packagesLogPrefix): \(packages.count) packages uit \(feeds.count) feeds")
            return .packages(packages)
        } catch FeedsDenied.needsPermission {
            logger.info("\(packagesLogPrefix): geen recht op de feeds, needsPermission")
            return .needsPermission(reason: PackagesPermission.azurePackagingRead(for: authMethod))
        } catch {
            logger.info("\(packagesLogPrefix): mislukt: \((error as? ProviderError)?.userMessage ?? error.localizedDescription)")
            throw error
        }
    }

    /// Het soort package uit `protocolType` van Azure Artifacts ("Npm", "NuGet", "PyPi", "UPack").
    static func packageType(protocolType: String) -> PublishedPackageType {
        switch protocolType.lowercased() {
        case "npm": .npm
        case "nuget": .nuGet
        case "maven": .maven
        case "pypi", "python": .pyPI
        case "cargo": .cargo
        case "upack", "universal": .universal
        default: PublishedPackageType(rawValue: protocolType)
        }
    }

    // MARK: - Verzoeken

    /// De feeds onder `base` (de organisatie of een project); leeg bij een 404.
    private func feedList(_ base: URL) async throws -> [FeedDTO] {
        let url = base.appending(path: "_apis/packaging/feeds")
        let (data, response) = try await send(url, apiVersion: "7.1")
        let feeds = (200..<300).contains(response.statusCode) && response.statusCode != 203
            ? try JSONDecoding.decode(ValueList<FeedDTO>.self, from: data).value : []
        logFeedsRequest(url, response: response, data: data, count: feeds.count)
        guard try Self.feedsAccess(response) else { return [] }
        try HTTPStatus.check(response, now: now())
        return feeds
    }

    /// De packages van één feed met hun nieuwste versie, zonder wat uit een upstream komt.
    private func packages(in feed: FeedDTO) async throws -> [PublishedPackage] {
        var base = feedsBaseURL
        if let project = feed.project?.name { base = base.appending(path: project) }
        let url = base.appending(path: "_apis/packaging/Feeds").appending(path: feed.id).appending(path: "packages")
        var result: [PublishedPackage] = []
        var skip = 0
        for _ in 0..<Self.feedPackagePages {
            let (data, response) = try await send(url, apiVersion: "7.1", query: [
                URLQueryItem(name: "includeUrls", value: "false"),
                URLQueryItem(name: "$top", value: String(pageSize)),
                URLQueryItem(name: "$skip", value: String(skip)),
            ])
            let page = (200..<300).contains(response.statusCode) && response.statusCode != 203
                ? try JSONDecoding.decode(ValueList<FeedPackageDTO>.self, from: data).value : []
            logFeedsRequest(url, response: response, data: data, count: page.count)
            guard try Self.feedsAccess(response) else { break }
            try HTTPStatus.check(response, now: now())
            for dto in page {
                if let package = try await package(from: dto, feed: feed) { result.append(package) }
            }
            if page.count < pageSize { break }
            skip += pageSize
        }
        return result
    }

    private func package(from dto: FeedPackageDTO, feed: FeedDTO) async throws -> PublishedPackage? {
        let listed = dto.versions ?? []
        guard let latest = listed.first(where: { $0.isLatest == true }) ?? listed.first,
              latest.isDeleted != true,
              // Bewaard uit een upstream (npmjs.com, nuget.org, een andere feed): niet van jou.
              latest.directUpstreamSourceId == nil else { return nil }
        let type = Self.packageType(protocolType: dto.protocolType)
        var base = baseURL
        if let project = feed.project?.name { base = base.appending(path: project) }
        // De pagina van een versie in Azure Artifacts; een "/" in de naam (npm-scope) wordt %2F.
        let page = { (version: String) in
            base.appending(path: "_artifacts/feed").appending(component: feed.name).appending(component: dto.protocolType)
                .appending(component: dto.name).appending(path: "overview").appending(component: version)
        }
        // Azure noemt de hoogste versie `isLatest`, ook als dat een pre-release is (#219). Dan de
        // versies van het package, zodat de hoogste stabiele release de nieuwste versie is en de
        // pre-release alleen genoemd wordt (`releasedVersion`, `newestPrerelease`), zoals bij een
        // image. Zonder stabiele versie blijft de pre-release de nieuwste versie.
        var versions = [latest]
        var readFailed = false
        if Version(latest.version)?.isPrerelease == true, let id = dto.id {
            if let all = try await allVersions(of: id, in: feed) {
                versions = Self.recentVersions(all, latest: latest)
            } else {
                readFailed = true
            }
        }
        let published = versions.map { version in
            PublishedVersion(version: version.version, publishedAt: version.publishDate.flatMap(DateParsing.parse), webURL: page(version.version))
        }
        // De pagina van het package is die van de versie die als nieuwste telt: de hoogste
        // stabiele (de versies staan hoogste eerst), anders `latest`.
        let shown = versions.first { Version($0.version)?.isPrerelease == false }?.version ?? latest.version
        return PublishedPackage(
            accountId: accountId, name: dto.name, type: type, owner: feed.project?.name ?? organization, repository: nil,
            webURL: page(shown), versions: published, versionsReadFailed: readFailed
        )
    }

    /// Alle versies van één package in een feed (Artifact Details - Get Package Versions). Leeg bij
    /// een 404; nil als het lezen mislukte (een 5xx, een time-out, een antwoord dat niet te lezen
    /// is), een mislukking van dit package, gelogd (#215). Een recht dat ontbreekt gaat door.
    private func allVersions(of packageId: String, in feed: FeedDTO) async throws -> [FeedPackageDTO.Version]? {
        var base = feedsBaseURL
        if let project = feed.project?.name { base = base.appending(path: project) }
        let url = base.appending(path: "_apis/packaging/Feeds").appending(path: feed.id).appending(path: "Packages")
            .appending(path: packageId).appending(path: "versions")
        do {
            let (data, response) = try await send(url, apiVersion: "7.1", query: [
                URLQueryItem(name: "includeUrls", value: "false"),
                URLQueryItem(name: "isDeleted", value: "false"),
            ])
            let versions = (200..<300).contains(response.statusCode) && response.statusCode != 203
                ? try JSONDecoding.decode(ValueList<FeedPackageDTO.Version>.self, from: data).value : []
            logFeedsRequest(url, response: response, data: data, count: versions.count)
            guard try Self.feedsAccess(response) else { return [] }
            try HTTPStatus.check(response, now: now())
            return versions
        } catch FeedsDenied.needsPermission {
            throw FeedsDenied.needsPermission
        } catch {
            let message = (error as? ProviderError)?.userMessage ?? error.localizedDescription
            logger.error("\(packagesLogPrefix): \(url.path(percentEncoded: true)) versies niet te lezen: \(message)")
            return nil
        }
    }

    /// De recente versies van eigen makelij, hoogste eerst, met `latest` erbij, gekort zoals elk
    /// register (`PublishedPackage.recentVersions`): hooguit `recentVersionLimit`, en altijd de
    /// hoogste stabiele release, ook achter veel pre-releases.
    static func recentVersions(_ all: [FeedPackageDTO.Version], latest: FeedPackageDTO.Version) -> [FeedPackageDTO.Version] {
        var seen: Set<String> = []
        let own = ([latest] + all.filter { $0.isDeleted != true && $0.directUpstreamSourceId == nil })
            .filter { seen.insert($0.version).inserted }
            .compactMap { item in Version(item.version).map { (item: item, version: $0) } }
            .sorted { $0.version > $1.version }
            .map(\.item)
        let recent = PublishedPackage.recentVersions(own, version: \.version)
        return recent.isEmpty ? [latest] : recent
    }

    /// false: niets te lezen (404). Gooit `needsPermission` bij 401 en bij een 403 die geen rate
    /// limit is; de rest (ook 203, een ongeldige PAT) gaat naar `HTTPStatus.check`.
    static func feedsAccess(_ response: HTTPURLResponse) throws -> Bool {
        switch response.statusCode {
        case 401:
            throw FeedsDenied.needsPermission
        case 403:
            if response.value(forHTTPHeaderField: "Retry-After") != nil { return true }
            throw FeedsDenied.needsPermission
        case 404:
            return false
        default:
            return true
        }
    }

    // MARK: - Loggen

    /// "azureDevOps/pat account <id>" voor elke logregel.
    private var packagesLogPrefix: String {
        "\(ProviderKind.azureDevOps.rawValue)/\(authMethod.rawValue) account \(accountId.uuidString)"
    }

    private func logFeedsRequest(_ url: URL, response: HTTPURLResponse, data: Data, count: Int) {
        let path = url.path(percentEncoded: true)
        let status = response.statusCode
        if (200..<300).contains(status) {
            logger.info("\(packagesLogPrefix): \(path) \(status), \(count)")
        } else {
            struct Message: Decodable { let message: String? }
            let message = (try? JSONDecoder().decode(Message.self, from: data))?.message ?? ""
            logger.info("\(packagesLogPrefix): \(path) \(status) \(message)")
        }
    }
}

private enum FeedsDenied: Error {
    case needsPermission
}

// MARK: - DTO's

/// Een feed van Azure Artifacts; `project` is nil bij een feed van de organisatie.
struct FeedDTO: Decodable {
    struct Project: Decodable {
        let name: String?
    }

    let id: String
    let name: String
    let project: Project?
    let deletedDate: String?
}

/// Een package in een feed, met (zonder `includeAllVersions`) alleen zijn nieuwste versie.
struct FeedPackageDTO: Decodable {
    struct Version: Decodable {
        let version: String
        let isLatest: Bool?
        let isDeleted: Bool?
        let publishDate: String?
        let directUpstreamSourceId: String?
    }

    let id: String?
    let name: String
    let protocolType: String
    let versions: [Version]?
}
