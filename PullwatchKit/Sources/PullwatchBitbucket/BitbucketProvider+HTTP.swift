import Foundation
import PullwatchCore

// MARK: - HTTP

extension BitbucketProvider {
    /// Tekens die in een padsegment ongecodeerd mogen; de rest (ook "/") wordt %XX.
    private static let segmentAllowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    static func encode(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? segment
    }

    /// `https://api.bitbucket.org/2.0/<segment>/<segment>…`, elk segment apart gecodeerd. Een
    /// repo ("workspace/repo") geef je als `repository(_:)`, zodat zijn "/" blijft staan.
    func endpoint(_ segments: String...) -> URL {
        URL(string: Self.api.absoluteString + "/" + segments.map(Self.encode).joined(separator: "/"))!
    }

    /// `…/repositories/<workspace>/<repo>/<segment>…`.
    func repository(_ repo: String, _ segments: String...) -> URL {
        let path = (repo.split(separator: "/").map(String.init) + segments).map(Self.encode).joined(separator: "/")
        return URL(string: Self.api.absoluteString + "/repositories/" + path)!
    }

    /// Bladert langs de `next`-links tot er geen meer is, `maxPages` op is of `stop` genoeg
    /// vindt. Een `next` naar een andere host volgt dit niet: het token gaat alleen naar de API.
    func pages<T: Decodable>(
        _ url: URL,
        query: [URLQueryItem],
        maxPages: Int,
        anonymous: Bool = false,
        stop: ([T]) -> Bool = { _ in false }
    ) async throws -> [T] {
        var result: [T] = []
        var next: URL? = Self.withQuery(url, query)
        var fetched = 0
        while let current = next, fetched < maxPages {
            let page: PageDTO<T> = try JSONDecoding.decode(
                PageDTO<T>.self, from: try await send(current, anonymous: anonymous).data, snakeCase: true
            )
            result += page.values
            fetched += 1
            if stop(result) { break }
            next = page.next.flatMap(URL.init(string:)).flatMap { Self.isAPI($0) && $0 != current ? $0 : nil }
        }
        return result
    }

    /// Ligt `url` op de API zelf (https, api.bitbucket.org, geen andere poort)?
    static func isAPI(_ url: URL) -> Bool {
        url.scheme == api.scheme && url.host() == api.host() && url.port == api.port
    }

    /// Zet de query achter `url`; "+" wordt %2B (tijden met een tijdzone, tagnamen als `1.0+build`).
    static func withQuery(_ url: URL, _ query: [URLQueryItem]) -> URL {
        guard !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = (components.queryItems ?? []) + query
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url ?? url
    }

    func get<T: Decodable>(_ url: URL, anonymous: Bool = false, query: [URLQueryItem] = []) async throws -> T {
        try JSONDecoding.decode(T.self, from: try await send(url, query: query, anonymous: anonymous).data, snakeCase: true)
    }

    /// De waarde van de `Authorization`-header: Basic met het e-mailadres van het Atlassian-account
    /// en het API-token (`e-mail:token`, base64), zoals Atlassian het voor API-tokens met scopes
    /// voorschrijft. Komt nooit in een log of foutmelding.
    static func basicAuthorization(email: String, token: String) -> String {
        "Basic " + Data("\(email):\(token)".utf8).base64EncodedString()
    }

    /// Een GET met Basic auth. 429 met `Retry-After` wordt `rateLimited`. Met `anonymous` zonder
    /// inloggen, voor een openbare losse repo; is die limiet op, dan gaan er tot de reset geen
    /// verzoeken zonder inloggen meer uit. Met `checked: false` zonder de status te controleren.
    func send(
        _ url: URL,
        query: [URLQueryItem] = [],
        anonymous: Bool = false,
        checked: Bool = true
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        if anonymous, let until = anonymousPausedUntil, until > now() { throw ProviderError.rateLimited(until: until) }
        var request = URLRequest(url: Self.withQuery(url, query))
        if !anonymous {
            guard let email, !email.isEmpty else { throw ProviderError.missingToken }
            let token = try await tokenSource.token()
            request.setValue(Self.basicAuthorization(email: email, token: token), forHTTPHeaderField: "Authorization")
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
