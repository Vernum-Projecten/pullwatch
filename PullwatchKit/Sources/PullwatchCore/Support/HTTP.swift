public import Foundation

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    /// Zonder cache: GitHub stuurt `Cache-Control: max-age=60`, en met `URLSession.shared` gaf
    /// een nieuwe vraag binnen die minuut het oude antwoord (een net toegevoegde installatie of
    /// PR bleef dan weg). Pullwatch wil bij elke poll en elke knop de stand van nu.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await Self.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ProviderError.network(String(localized: "geen HTTP-antwoord", bundle: .localizedCore))
            }
            return (data, http)
        } catch {
            throw Self.providerError(for: error, request: request)
        }
    }

    /// Een certificaat dat macOS niet vertrouwt: zelfondertekend, van een onbekende CA, verlopen
    /// of nog niet geldig. Pullwatch maakt daar geen uitzondering voor (het token gaat erheen).
    static let untrustedCertificateCodes: Set<URLError.Code> = [
        .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateHasBadDate,
        .serverCertificateNotYetValid,
    ]

    /// Wat een fout van `URLSession` voor Pullwatch betekent. Een timeout krijgt een eigen,
    /// vertaalde tekst met de host; de rest blijft een netwerkfout met de tekst van het systeem.
    static func providerError(for error: any Error, request: URLRequest) -> ProviderError {
        switch error {
        case let error as ProviderError:
            return error
        case let error as URLError where error.code == .timedOut:
            return .timeout(command: request.url?.host() ?? request.url?.absoluteString ?? "")
        case let error as URLError where untrustedCertificateCodes.contains(error.code):
            return .untrustedCertificate(request.url?.host() ?? request.url?.absoluteString ?? "")
        default:
            return .network(error.localizedDescription)
        }
    }
}

public enum HTTPStatus {
    public static func check(_ response: HTTPURLResponse, now: Date) throws {
        let status = response.statusCode
        switch status {
        case 203:
            // Azure DevOps antwoordt met 203 + HTML-loginpagina bij een ongeldige PAT.
            throw ProviderError.unauthorized
        case 200..<300:
            return
        case 401:
            throw ProviderError.unauthorized
        case 403, 429:
            if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"), let seconds = Double(retryAfter) {
                throw ProviderError.rateLimited(until: now + seconds)
            }
            if response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0",
               let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
               let epoch = Double(reset) {
                throw ProviderError.rateLimited(until: Date(timeIntervalSince1970: epoch))
            }
            // GitLab noemt dezelfde headers zonder "X-".
            if response.value(forHTTPHeaderField: "RateLimit-Remaining") == "0",
               let reset = response.value(forHTTPHeaderField: "RateLimit-Reset"),
               let epoch = Double(reset) {
                throw ProviderError.rateLimited(until: Date(timeIntervalSince1970: epoch))
            }
            if status == 429 { throw ProviderError.rateLimited(until: now + 60) }
            throw ProviderError.unauthorized
        default:
            throw ProviderError.server(status: status)
        }
    }
}

public enum JSONDecoding {
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data, snakeCase: Bool = false) throws -> T {
        let decoder = JSONDecoder()
        if snakeCase { decoder.keyDecodingStrategy = .convertFromSnakeCase }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ProviderError.decoding("\(T.self): \(error.localizedDescription)")
        }
    }
}

public enum DateParsing {
    /// ISO-8601; fractionele seconden (ook 7 cijfers zoals Azure DevOps levert) worden genegeerd.
    public static func parse(_ string: String) -> Date? {
        var value = string
        if let dot = value.firstIndex(of: "."),
           let end = value[dot...].firstIndex(where: { "Z+-".contains($0) }) {
            value.removeSubrange(dot..<end)
        }
        return try? Date(value, strategy: .iso8601)
    }
}
