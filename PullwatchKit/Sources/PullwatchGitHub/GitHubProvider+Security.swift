import Foundation
import PullwatchCore

/// Beveiligingsgegevens van GitHub zelf: code scanning, het aantal open geheimen en de eigen
/// gepubliceerde adviezen van de repository. Eén verzoek per soort (100 per pagina, `Link`-header
/// voor de volgende). Een 403 of 404 is geen fout: dan staat het uit of mag de app het niet.
extension GitHubProvider {
    public func securityAlerts(in repo: String) async throws -> SecurityScan? {
        let base = apiBase.appending(path: "repos").appending(path: repo)
        let web = URL(string: "https://github.com")!.appending(path: repo).appending(path: "security")
        var feeds: [SecurityFeed] = []

        // Code scanning: alleen open meldingen.
        var alerts: [SecurityAlert] = []
        let codeLink = web.appending(path: "code-scanning")
        do {
            let items: [CodeScanningAlertDTO] = try await allPages(
                base.appending(path: "code-scanning/alerts"),
                query: [URLQueryItem(name: "state", value: "open"), URLQueryItem(name: "per_page", value: String(pageSize))]
            )
            alerts = items.compactMap { $0.alert(repoPage: codeLink) }
            feeds.append(SecurityFeed(kind: .codeScanning, availability: .available, link: codeLink))
        } catch {
            feeds.append(await feed(.codeScanning, repo: repo, error: error, settings: codeLink))
        }

        // Secret scanning: alleen tellen; `hide_secret` zodat het geheim zelf nooit binnenkomt.
        var secretCount: Int?
        let secretLink = web.appending(path: "secret-scanning")
        do {
            let items: [SecretAlertDTO] = try await allPages(
                base.appending(path: "secret-scanning/alerts"),
                query: [
                    URLQueryItem(name: "state", value: "open"),
                    URLQueryItem(name: "hide_secret", value: "true"),
                    URLQueryItem(name: "per_page", value: String(pageSize)),
                ]
            )
            secretCount = items.count
            feeds.append(SecurityFeed(kind: .secretScanning, availability: .available, link: secretLink))
        } catch {
            feeds.append(await feed(.secretScanning, repo: repo, error: error, settings: secretLink))
        }

        // Eigen adviezen die de repository gepubliceerd heeft.
        var advisories: [GitHubAdvisory] = []
        let advisoryLink = web.appending(path: "advisories")
        do {
            let items: [AdvisoryDTO] = try await allPages(
                base.appending(path: "security-advisories"),
                query: [URLQueryItem(name: "state", value: "published"), URLQueryItem(name: "per_page", value: String(pageSize))]
            )
            let date = now()
            advisories = items.map { $0.advisory(fetchedAt: date, withPackages: true) }
            feeds.append(SecurityFeed(kind: .repositoryAdvisories, availability: .available, link: advisoryLink))
        } catch {
            feeds.append(await feed(.repositoryAdvisories, repo: repo, error: error, settings: advisoryLink))
        }

        return SecurityScan(feeds: feeds, alerts: alerts, secretCount: secretCount, advisories: advisories)
    }

    public func advisoryDatabaseToken() async -> String? {
        try? await tokenSource.token()
    }

    /// Wat een mislukte soort betekent: geen recht (met de pagina van de installatie, waar de
    /// eigenaar het goedkeurt), staat uit, of een echte fout.
    private func feed(_ kind: SecurityFeed.Kind, repo: String, error: any Error, settings: URL) async -> SecurityFeed {
        switch error {
        case SecurityAccess.needsPermission:
            return SecurityFeed(kind: kind, availability: .needsPermission, link: await installationsURL(for: repo))
        case SecurityAccess.notEnabled:
            return SecurityFeed(kind: kind, availability: .notEnabled, link: settings)
        default:
            return SecurityFeed(
                kind: kind, availability: .failed, message: (error as? ProviderError)?.userMessage ?? error.localizedDescription
            )
        }
    }

    /// Waar de eigenaar van de repo de installaties van GitHub Apps beheert en een nieuw recht goedkeurt.
    private func installationsURL(for repo: String) async -> URL {
        let owner = String(repo.split(separator: "/").first ?? "")
        if (try? await resolveOwnerKind(owner)) == .organization {
            return URL(string: "https://github.com/organizations")!.appending(path: owner).appending(path: "settings/installations")
        }
        return URL(string: "https://github.com/settings/installations")!
    }

    /// Alle pagina's van een lijst, via de `next`-link, hooguit `maxPages`.
    private func allPages<T: Decodable>(_ url: URL, query: [URLQueryItem]) async throws -> [T] {
        var items: [T] = []
        var next: (url: URL, query: [URLQueryItem])? = (url, query)
        var pages = 0
        while let current = next, pages < maxPages {
            let (data, response) = try await send(current.url, query: current.query, checked: false)
            try Self.checkAccess(response, data: data)
            try HTTPStatus.check(response, now: now())
            items += try JSONDecoding.decode([T].self, from: data, snakeCase: true)
            next = Self.nextLink(response).map { ($0, []) }
            pages += 1
        }
        return items
    }

    /// 404: staat uit (of geen analyse); 403 zonder rate limit: geen recht ("Resource not
    /// accessible by integration") of de functie staat uit ("Advanced Security must be enabled").
    static func checkAccess(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 404:
            throw SecurityAccess.notEnabled
        case 403:
            let rateLimited = response.value(forHTTPHeaderField: "Retry-After") != nil
                || response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
            guard !rateLimited else { return }
            struct Message: Decodable { let message: String? }
            let message = (try? JSONDecoder().decode(Message.self, from: data))?.message ?? ""
            let permission = message.localizedCaseInsensitiveContains("not accessible")
                || message.localizedCaseInsensitiveContains("permission")
            throw permission ? SecurityAccess.needsPermission : SecurityAccess.notEnabled
        default:
            return
        }
    }

    /// `<https://api.github.com/…&after=…>; rel="next", <…>; rel="last"`.
    static func nextLink(_ response: HTTPURLResponse) -> URL? {
        guard let header = response.value(forHTTPHeaderField: "Link") else { return nil }
        for part in header.split(separator: ",") {
            let pieces = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.dropFirst().contains(where: { $0 == "rel=\"next\"" }),
                  let first = pieces.first, first.hasPrefix("<"), first.hasSuffix(">") else { continue }
            return URL(string: String(first.dropFirst().dropLast()))
        }
        return nil
    }
}

enum SecurityAccess: Error {
    case notEnabled
    case needsPermission
}

private struct CodeScanningAlertDTO: Decodable {
    struct Rule: Decodable {
        let id: String?
        let name: String?
        let severity: String?
        let securitySeverityLevel: String?
        let description: String?
    }

    struct Tool: Decodable {
        let name: String?
    }

    struct Instance: Decodable {
        struct Location: Decodable {
            let path: String?
            let startLine: Int?
        }
        struct Message: Decodable {
            let text: String?
        }
        let location: Location?
        let message: Message?
    }

    let number: Int
    let htmlUrl: String?
    let createdAt: String?
    let rule: Rule?
    let tool: Tool?
    let mostRecentInstance: Instance?

    func alert(repoPage: URL) -> SecurityAlert? {
        let title = [rule?.description, mostRecentInstance?.message?.text, rule?.name, rule?.id]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return SecurityAlert(
            source: .codeScanning,
            kind: .code,
            number: number,
            title: title ?? "#\(number)",
            rule: rule?.id,
            tool: tool?.name,
            severity: GitHubAdvisory.securitySeverity(rule?.securitySeverityLevel),
            toolSeverity: rule?.severity,
            path: mostRecentInstance?.location?.path,
            line: mostRecentInstance?.location?.startLine,
            url: htmlUrl.flatMap(URL.init(string:)) ?? repoPage.appending(path: String(number)),
            createdAt: createdAt.flatMap(DateParsing.parse)
        )
    }
}

/// Alleen het nummer: het geheim zelf leest Pullwatch nooit.
private struct SecretAlertDTO: Decodable {
    let number: Int
}
