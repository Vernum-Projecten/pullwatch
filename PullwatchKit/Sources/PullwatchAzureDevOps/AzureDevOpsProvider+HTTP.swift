import Foundation
import PullwatchCore

// MARK: - HTTP

extension AzureDevOpsProvider {
    private func authorizationHeader() async throws -> String {
        let token = try await tokenSource.token()
        switch authMethod {
        case .pat: return "Basic " + Data(":\(token)".utf8).base64EncodedString()
        case .cli, .gitHubApp: return "Bearer \(token)"
        }
    }

    func get<T: Decodable>(
        _ url: URL,
        apiVersion: String = "7.1",
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> T {
        let (data, response) = try await send(url, apiVersion: apiVersion, query: query, body: body)
        try HTTPStatus.check(response, now: now())
        return try JSONDecoding.decode(T.self, from: data)
    }

    /// Het verzoek met autorisatie en api-version, zonder de status te controleren.
    func send(
        _ url: URL,
        apiVersion: String,
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = query + [URLQueryItem(name: "api-version", value: apiVersion)]
        // URLComponents laat "+" staan, maar een server leest dat als spatie (vervolgtokens hebben er soms een).
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: components.url!)
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let authorization = try await authorizationHeader()
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await http.send(request)
    }
}
