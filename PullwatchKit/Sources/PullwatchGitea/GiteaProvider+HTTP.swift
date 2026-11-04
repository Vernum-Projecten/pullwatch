import Foundation
import PullwatchCore

// MARK: - HTTP

extension GiteaProvider {
    /// Tekens die in een padsegment ongecodeerd mogen; de rest wordt %XX.
    private static let segmentAllowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    static func encode(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? segment
    }

    /// `<server>/api/v1/<segment>/<segment>…`, elk segment apart gecodeerd.
    func endpoint(_ segments: String...) -> URL {
        endpoint(segments)
    }

    func endpoint(_ segments: [String]) -> URL {
        URL(string: instanceURL.absoluteString + "/api/v1/" + segments.map(Self.encode).joined(separator: "/"))!
    }

    /// `<server>/api/v1/repos/<eigenaar>/<repo>/<segment>…`.
    func repoEndpoint(_ repo: String, _ segments: String...) -> URL {
        endpoint(["repos"] + repo.split(separator: "/", maxSplits: 1).map(String.init) + segments)
    }

    /// Een pagina op de server: `<server>/<eigenaar>/<repo>/<segment>…`.
    func webURL(_ repo: String, _ segments: String...) -> URL? {
        let parts = repo.split(separator: "/").map(String.init) + segments
        return URL(string: instanceURL.absoluteString + "/" + parts.map(Self.encode).joined(separator: "/"))
    }

    /// Bladert met `page` en `limit`: volgt de `Link` met `rel="next"` (alleen op dezelfde server,
    /// `PageLink.follow`: het token gaat nooit naar een andere host), en zonder `Link` de volgende pagina zolang een
    /// pagina vol is en `X-Total-Count` meer belooft. Hooguit `maxPages` pagina's, of tot `stop`
    /// genoeg vindt.
    func pages<T: Decodable>(
        _ url: URL,
        query: [URLQueryItem],
        maxPages: Int,
        anonymous: Bool = false,
        stop: ([T]) -> Bool = { _ in false }
    ) async throws -> [T] {
        var result: [T] = []
        var page = 1
        var next: URL? = Self.withQuery(url, query + pageQuery(page))
        while let current = next, page <= maxPages {
            let (data, response) = try await send(current, anonymous: anonymous)
            let items = try JSONDecoding.decode([T].self, from: data, snakeCase: true)
            result += items
            if stop(result) || items.isEmpty { break }
            page += 1
            if let link = response.value(forHTTPHeaderField: "Link") {
                next = PageLink.follow(PageLink.next(inHeader: link), after: current, api: instanceURL)
            } else if items.count >= pageSize,
                      let total = response.value(forHTTPHeaderField: "X-Total-Count").flatMap(Int.init), total > result.count {
                next = Self.withQuery(url, query + pageQuery(page))
            } else {
                next = nil
            }
        }
        return result
    }

    private func pageQuery(_ page: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "limit", value: String(pageSize)), URLQueryItem(name: "page", value: String(page))]
    }

    /// Zet de query achter `url`; "+" wordt %2B (tijden met een tijdzone, tagnamen als `1.0+build`).
    static func withQuery(_ url: URL, _ query: [URLQueryItem]) -> URL {
        guard !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = query
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url ?? url
    }

    func get<T: Decodable>(_ url: URL, anonymous: Bool = false, query: [URLQueryItem] = []) async throws -> T {
        try JSONDecoding.decode(T.self, from: try await send(url, query: query, anonymous: anonymous).data, snakeCase: true)
    }

    /// Een GET met het token (`Authorization: token …`, wat Gitea en Forgejo allebei kennen). 429
    /// wordt `rateLimited`; 403 met "required scope(s)" wordt `missingScope` met de scope die de
    /// server noemt. Met `anonymous` zonder token, voor een openbare losse repo; is die limiet op,
    /// dan gaan er tot de reset geen verzoeken zonder token meer uit. Met `checked: false` zonder
    /// de status te controleren.
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
            request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await http.send(request)
        if checked {
            if response.statusCode == 403, let scope = Self.missingScope(in: data) {
                throw ProviderError.missingScope(scope)
            }
            do {
                try HTTPStatus.check(response, now: now())
            } catch ProviderError.rateLimited(let until) where anonymous {
                anonymousPausedUntil = until
                throw ProviderError.rateLimited(until: until)
            }
        }
        return (data, response)
    }

    /// De scope uit een 403 van een token zonder die scope. Forgejo: "token does not have at
    /// least one of required scope(s): [read:issue]"; Gitea: "…required scope(s), required=
    /// [read:issue], token scope=…". Bij meer scopes de eerste.
    static func missingScope(in data: Data) -> String? {
        guard let message = (try? JSONDecoder().decode(ErrorDTO.self, from: data))?.message,
              let marker = message.range(of: "required scope") else { return nil }
        let rest = message[marker.upperBound...]
        guard let open = rest.firstIndex(of: "["), let close = rest[open...].firstIndex(of: "]") else { return nil }
        let scopes = rest[rest.index(after: open)..<close].split(whereSeparator: { $0 == " " || $0 == "," })
        return scopes.first.map(String.init)
    }
}
