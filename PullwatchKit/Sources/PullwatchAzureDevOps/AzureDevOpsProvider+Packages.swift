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
            result += page.compactMap { package(from: $0, feed: feed) }
            if page.count < pageSize { break }
            skip += pageSize
        }
        return result
    }

    private func package(from dto: FeedPackageDTO, feed: FeedDTO) -> PublishedPackage? {
        let versions = dto.versions ?? []
        guard let latest = versions.first(where: { $0.isLatest == true }) ?? versions.first,
              latest.isDeleted != true,
              // Bewaard uit een upstream (npmjs.com, nuget.org, een andere feed): niet van jou.
              latest.directUpstreamSourceId == nil else { return nil }
        let type = Self.packageType(protocolType: dto.protocolType)
        var page = baseURL
        if let project = feed.project?.name { page = page.appending(path: project) }
        // De pagina van de versie in Azure Artifacts; een "/" in de naam (npm-scope) wordt %2F.
        page = page.appending(path: "_artifacts/feed").appending(component: feed.name).appending(component: dto.protocolType)
            .appending(component: dto.name).appending(path: "overview").appending(component: latest.version)
        return PublishedPackage(
            accountId: accountId, name: dto.name, type: type, owner: feed.project?.name ?? organization, repository: nil,
            webURL: page,
            versions: [PublishedVersion(version: latest.version, publishedAt: latest.publishDate.flatMap(DateParsing.parse), webURL: page)]
        )
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

    let name: String
    let protocolType: String
    let versions: [Version]?
}
