import Foundation
import PullwatchCore

// MARK: - HTTP

extension GitLabProvider {
    /// Tekens die in een padsegment ongecodeerd mogen; de rest (ook "/", "." blijft) wordt %XX.
    /// GitLab wil een project of bestand als één segment: `groep%2Fproject`, `src%2Fmain.swift`.
    private static let segmentAllowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    static func encode(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? segment
    }

    /// `<server>/api/v4/<segment>/<segment>…`, elk segment apart gecodeerd.
    func endpoint(_ segments: String...) -> URL {
        URL(string: instanceURL.absoluteString + "/api/v4/" + segments.map(Self.encode).joined(separator: "/"))!
    }

    /// Een pagina op de server: de repo houdt zijn "/" (`groep/project`), de rest wordt gecodeerd.
    func webURL(_ repo: String, _ segments: String...) -> URL? {
        let repoPath = repo.split(separator: "/").map { Self.encode(String($0)) }.joined(separator: "/")
        return URL(string: instanceURL.absoluteString + "/" + repoPath + "/" + segments.map(Self.encode).joined(separator: "/"))
    }

    /// Bladert met `page` tot de server geen `x-next-page` meer noemt (of `stop` genoeg vindt).
    /// Antwoordt de server met keyset-paginering (alleen een `Link` met `rel="next"`), dan volgt
    /// dit die link, maar alleen op dezelfde server (`PageLink.follow`): het token gaat nooit naar
    /// een andere host.
    /// Met `anonymous` zonder token: alleen voor openbare losse projecten.
    func pages<T: Decodable>(
        _ url: URL,
        query: [URLQueryItem],
        maxPages: Int,
        anonymous: Bool = false,
        stop: ([T]) -> Bool = { _ in false }
    ) async throws -> [T] {
        var result: [T] = []
        var next: URL? = Self.withQuery(url, query + [
            URLQueryItem(name: "per_page", value: String(pageSize)),
            URLQueryItem(name: "page", value: "1"),
        ])
        var fetched = 0
        while let current = next, fetched < maxPages {
            let (data, response) = try await send(current, anonymous: anonymous)
            result += try JSONDecoding.decode([T].self, from: data, snakeCase: true)
            fetched += 1
            if stop(result) { break }
            next = nextPage(after: current, response: response, base: url, query: query)
        }
        return result
    }

    func nextPage(after current: URL, response: HTTPURLResponse, base: URL, query: [URLQueryItem]) -> URL? {
        if let page = response.value(forHTTPHeaderField: "x-next-page")?.trimmingCharacters(in: .whitespaces), !page.isEmpty {
            guard Int(page) != nil else { return nil }
            return Self.withQuery(base, query + [
                URLQueryItem(name: "per_page", value: String(pageSize)),
                URLQueryItem(name: "page", value: page),
            ])
        }
        return PageLink.follow(PageLink.next(in: response), after: current, api: instanceURL)
    }

    /// De URL met `rel="next"` uit een `Link`-header (RFC 8288), via `PageLink`.
    static func nextLink(in header: String) -> URL? {
        PageLink.next(inHeader: header)
    }

    /// Zet de query achter `url`; "+" wordt %2B, anders leest GitLab het als spatie (tagnamen als
    /// `1.0+build`, tijden met een tijdzone).
    static func withQuery(_ url: URL, _ query: [URLQueryItem]) -> URL {
        guard !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = query
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url ?? url
    }

    func get<T: Decodable>(_ url: URL, anonymous: Bool = false, query: [URLQueryItem] = []) async throws -> T {
        try JSONDecoding.decode(T.self, from: try await send(url, query: query, anonymous: anonymous).data, snakeCase: true)
    }

    /// Een GET met het token als Bearer (een personal access token en het OAuth-token van `glab`
    /// werken allebei zo). 429 met `Retry-After` of `RateLimit-Reset` wordt `rateLimited`.
    /// Met `anonymous` zonder token, voor een openbaar los project; is die limiet op, dan gaan er
    /// tot de reset geen verzoeken zonder token meer uit. Met `checked: false` zonder de status te
    /// controleren (de controle van een los project leest 401, 403 en 404 zelf).
    func send(
        _ url: URL,
        query: [URLQueryItem] = [],
        anonymous: Bool = false,
        checked: Bool = true
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        if anonymous, let until = anonymousPausedUntil, until > now() { throw ProviderError.rateLimited(until: until) }
        var request = URLRequest(url: Self.withQuery(url, query))
        if !anonymous {
            let token = try await tokenSource.token()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await http.send(request)
        if checked {
            do {
                try HTTPStatus.check(response, now: now())
            } catch ProviderError.rateLimited(let until) where anonymous {
                anonymousPausedUntil = until
                throw ProviderError.rateLimited(until: until)
            }
        }
        return (data, response)
    }
}
