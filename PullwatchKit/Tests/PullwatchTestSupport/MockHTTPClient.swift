import Foundation
import PullwatchCore

/// Route-matching op substring van de volledige URL; de EERSTE geregistreerde match wint.
/// Registreer dus specifieke routes vóór algemene.
package final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    package init() {}

    private struct Route {
        let substring: String
        let status: Int
        let headers: [String: String]
        let body: String
        /// Alleen voor verzoeken met (`true`) of zonder (`false`) `Authorization`; nil: allebei.
        var authorized: Bool? = nil
    }

    private let lock = NSLock()
    private var routes: [Route] = []
    private var recorded: [URLRequest] = []
    private var sequences: [String: [String]] = [:]

    package var requests: [URLRequest] { lock.withLock { recorded } }

    package func on(_ substring: String, status: Int = 200, headers: [String: String] = [:], body: String) {
        lock.withLock { routes.append(Route(substring: substring, status: status, headers: headers, body: body)) }
    }

    /// Als `on`, maar alleen voor verzoeken met (`authorized: true`) of zonder token.
    package func on(_ substring: String, authorized: Bool, status: Int = 200, headers: [String: String] = [:], body: String) {
        lock.withLock {
            routes.append(Route(substring: substring, status: status, headers: headers, body: body, authorized: authorized))
        }
    }

    /// Antwoorden die na elkaar komen voor dezelfde route; het laatste blijft daarna gelden.
    package func onSequence(_ substring: String, bodies: [String]) {
        lock.withLock { sequences[substring, default: []].append(contentsOf: bodies) }
    }

    package func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let route: Route? = lock.withLock {
            recorded.append(request)
            if let key = sequences.keys.first(where: { url.absoluteString.contains($0) }), let body = sequences[key]?.first {
                if sequences[key]!.count > 1 { sequences[key]!.removeFirst() }
                return Route(substring: key, status: 200, headers: [:], body: body)
            }
            let authorized = request.value(forHTTPHeaderField: "Authorization") != nil
            return routes.first { route in
                url.absoluteString.contains(route.substring) && (route.authorized.map { $0 == authorized } ?? true)
            }
        }
        guard let route else { throw ProviderError.network("geen mock-route voor \(url.absoluteString)") }
        let response = HTTPURLResponse(url: url, statusCode: route.status, httpVersion: nil, headerFields: route.headers)!
        return (Data(route.body.utf8), response)
    }
}
