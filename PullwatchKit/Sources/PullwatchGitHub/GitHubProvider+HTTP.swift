import Foundation
import PullwatchCore

// MARK: - HTTP

extension GitHubProvider {
    func get<T: Decodable>(_ url: URL, query: [URLQueryItem] = []) async throws -> T {
        try JSONDecoding.decode(T.self, from: try await send(url, query: query).data, snakeCase: true)
    }

    /// Met `checked: false` zonder de status te controleren (de beveiligingsgegevens lezen 403
    /// en 404 zelf). Met `anonymous` zonder token: alleen voor openbare losse repo's.
    func send(
        _ url: URL,
        query: [URLQueryItem] = [],
        accept: String = "application/vnd.github+json",
        body: Data? = nil,
        checked: Bool = true,
        anonymous: Bool = false
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if !anonymous {
            let token = try await tokenSource.token()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await http.send(request)
        if checked { try HTTPStatus.check(response, now: now()) }
        return (data, response)
    }
}

extension Array {
    /// Opeenvolgende stukken van hooguit `size` elementen.
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
