public import Foundation
public import PullwatchCore

// Inloggen bij GitHub via de Pullwatch GitHub App met de device flow (RFC 8628), overgenomen uit
// FerroLICENCE (`GitHubKit/Auth.swift`). Geen client secret: de client id is openbaar.
// Instellen: docs/github-app.md.

/// De GitHub App waarmee Pullwatch inlogt. Leeg als de app nog niet is aangemaakt.
public struct GitHubAppConfig: Sendable, Equatable {
    public var clientID: String
    /// Naam in `github.com/apps/<slug>`, voor de installatiepagina.
    public var slug: String
    public var web: URL

    public init(clientID: String, slug: String, web: URL = URL(string: "https://github.com")!) {
        self.clientID = clientID
        self.slug = slug
        self.web = web
    }

    public var isConfigured: Bool { !clientID.isEmpty }

    /// Uit de Info.plist van de app (`PWGitHubClientID`, `PWGitHubAppSlug`, gezet vanuit
    /// `App.xcconfig`); leeg zolang de GitHub App nog niet bestaat.
    public static var main: GitHubAppConfig {
        let info = Bundle.main.infoDictionary ?? [:]
        return GitHubAppConfig(
            clientID: (info["PWGitHubClientID"] as? String ?? "").trimmingCharacters(in: .whitespaces),
            slug: (info["PWGitHubAppSlug"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        )
    }

    /// Waar iemand de app op zijn account of organisatie installeert.
    public var installURL: URL { web.appending(path: "apps/\(slug)/installations/new") }
}

/// Een plek waar de GitHub App geïnstalleerd is: het eigen account of een organisatie.
public struct GitHubOwner: Hashable, Sendable, Identifiable {
    public var login: String
    public var isOrganization: Bool
    /// Het account van wie er is ingelogd.
    public var isSignedInUser = false

    public var id: String { login }

    public init(login: String, isOrganization: Bool, isSignedInUser: Bool = false) {
        self.login = login
        self.isOrganization = isOrganization
        self.isSignedInUser = isSignedInUser
    }
}

/// Een user access token en zijn refresh token: het token geldt 8 uur, de refresh token 6 maanden.
public struct GitHubAppTokens: Codable, Sendable, Equatable {
    public var access: String
    public var accessExpires: Date
    public var refresh: String?
    var refreshExpires: Date?

    public init(access: String, accessExpires: Date, refresh: String? = nil, refreshExpires: Date? = nil) {
        self.access = access
        self.accessExpires = accessExpires
        self.refresh = refresh
        self.refreshExpires = refreshExpires
    }
}

/// Waarom inloggen niet lukte.
public enum GitHubSignInError: Error, Equatable, Sendable {
    case expired
    case denied
    case notSignedIn
    case notConfigured
    case github(String)

    public var userMessage: String {
        switch self {
        case .expired: String(localized: "De code is verlopen. Begin opnieuw.", bundle: .localizedGitHub)
        case .denied: String(localized: "GitHub heeft het geweigerd. Begin opnieuw en keur Pullwatch goed.", bundle: .localizedGitHub)
        case .notSignedIn: String(localized: "Log opnieuw in bij GitHub.", bundle: .localizedGitHub)
        case .notConfigured: String(localized: "Inloggen bij GitHub is in deze versie nog niet ingesteld.", bundle: .localizedGitHub)
        case .github(let message): String(localized: "GitHub antwoordde: \(message)", bundle: .localizedGitHub)
        }
    }
}

/// De code die iemand op github.com/login/device intypt.
public struct DeviceCode: Sendable, Equatable {
    public let userCode: String
    public let verificationURL: URL
    public let expiresAt: Date
    let deviceCode: String
    let interval: Int

    public init(userCode: String, verificationURL: URL, expiresAt: Date, deviceCode: String, interval: Int) {
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.expiresAt = expiresAt
        self.deviceCode = deviceCode
        self.interval = interval
    }
}

/// De device flow van een GitHub App: toon een code, de persoon voert die in op github.com, de app
/// vraagt tot GitHub een token geeft.
public struct GitHubDeviceFlow: Sendable {
    let config: GitHubAppConfig
    let http: any HTTPClient
    let now: @Sendable () -> Date
    /// Hoe lang één seconde van GitHubs wachttijd duurt; korter in tests.
    var second: Duration

    public init(
        config: GitHubAppConfig,
        http: any HTTPClient = URLSessionHTTPClient(),
        now: @escaping @Sendable () -> Date = { Date() },
        second: Duration = .seconds(1)
    ) {
        self.config = config
        self.http = http
        self.now = now
        self.second = second
    }

    private func post<T: Decodable>(_ path: String, _ form: [String: String]) async throws -> T {
        guard config.isConfigured else { throw GitHubSignInError.notConfigured }
        var request = URLRequest(url: config.web.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await http.send(request)
        try HTTPStatus.check(response, now: now())
        return try JSONDecoding.decode(T.self, from: data, snakeCase: true)
    }

    public func start() async throws -> DeviceCode {
        struct Response: Decodable {
            let deviceCode: String
            let userCode: String
            let verificationUri: String
            let expiresIn: Int
            let interval: Int
        }
        let response: Response = try await post("login/device/code", ["client_id": config.clientID])
        return DeviceCode(
            userCode: response.userCode,
            verificationURL: URL(string: response.verificationUri) ?? config.web.appending(path: "login/device"),
            expiresAt: now().addingTimeInterval(TimeInterval(response.expiresIn)),
            deviceCode: response.deviceCode,
            interval: response.interval
        )
    }

    private struct TokenResponse: Decodable {
        let accessToken: String?
        let expiresIn: Int?
        let refreshToken: String?
        let refreshTokenExpiresIn: Int?
        let error: String?
        let interval: Int?

        func tokens(now: Date) -> GitHubAppTokens? {
            guard let accessToken else { return nil }
            return GitHubAppTokens(
                access: accessToken,
                accessExpires: now.addingTimeInterval(TimeInterval(expiresIn ?? 8 * 3600)),
                refresh: refreshToken,
                refreshExpires: refreshTokenExpiresIn.map { now.addingTimeInterval(TimeInterval($0)) }
            )
        }
    }

    /// Vraagt tot GitHub goedkeurt, weigert of de code verloopt.
    public func waitForTokens(_ code: DeviceCode) async throws -> GitHubAppTokens {
        var interval = max(code.interval, 1)
        while now() < code.expiresAt {
            try await Task.sleep(for: second * interval)
            let response: TokenResponse = try await post(
                "login/oauth/access_token",
                [
                    "client_id": config.clientID,
                    "device_code": code.deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                ]
            )
            if let tokens = response.tokens(now: now()) { return tokens }
            switch response.error {
            case "authorization_pending": continue
            case "slow_down": interval = response.interval ?? interval + 5
            case "expired_token": throw GitHubSignInError.expired
            case "access_denied": throw GitHubSignInError.denied
            default: throw GitHubSignInError.github(response.error ?? "onbekend antwoord")
            }
        }
        throw GitHubSignInError.expired
    }

    /// Een nieuw token met de refresh token; het oude paar werkt daarna niet meer.
    public func refresh(_ tokens: GitHubAppTokens) async throws -> GitHubAppTokens {
        guard let refresh = tokens.refresh else { throw GitHubSignInError.notSignedIn }
        let response: TokenResponse = try await post(
            "login/oauth/access_token",
            ["client_id": config.clientID, "grant_type": "refresh_token", "refresh_token": refresh]
        )
        guard let fresh = response.tokens(now: now()) else { throw GitHubSignInError.notSignedIn }
        return fresh
    }
}

/// De tokens van één account in de Keychain (nooit in een bestand), als JSON.
public struct GitHubAppTokenStore: Sendable {
    let secrets: any SecretStore
    let key: String

    public init(accountId: UUID, secrets: any SecretStore = SecretStores.shared) {
        self.secrets = secrets
        key = "github-app.\(accountId.uuidString)"
    }

    public func load() -> GitHubAppTokens? {
        guard let json = try? secrets.read(account: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(GitHubAppTokens.self, from: Data(json.utf8))
    }

    public func save(_ tokens: GitHubAppTokens) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try secrets.write(String(decoding: try encoder.encode(tokens), as: UTF8.self), account: key)
    }

    public func delete() {
        try? secrets.delete(account: key)
    }
}

/// Geeft een geldig access token, ververst het twee minuten voor het verloopt en bewaart het nieuwe paar.
/// Verversen en bewaren loopt via `GitHubAppTokenRefresher`: één keer tegelijk per account, en zonder
/// dat een afgebroken poll het nieuwe paar kwijtraakt.
public actor GitHubAppTokenSource: TokenSource {
    let flow: GitHubDeviceFlow
    let store: GitHubAppTokenStore
    let now: @Sendable () -> Date
    let refresher: GitHubAppTokenRefresher

    public init(flow: GitHubDeviceFlow, store: GitHubAppTokenStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(flow: flow, store: store, now: now, refresher: .shared)
    }

    init(flow: GitHubDeviceFlow, store: GitHubAppTokenStore, now: @escaping @Sendable () -> Date, refresher: GitHubAppTokenRefresher) {
        self.flow = flow
        self.store = store
        self.now = now
        self.refresher = refresher
    }

    public func token() async throws -> String {
        do {
            return try await refresher.validTokens(store: store, flow: flow, now: now).access
        } catch let error as ProviderError {
            // Netwerk of rate limit: niet uitloggen, later opnieuw.
            throw error
        } catch {
            // De refresh token geldt niet meer: opnieuw inloggen.
            throw ProviderError.unauthorized
        }
    }

    /// Een 401 met een token dat nog niet verlopen was: de volgende keer meteen verversen.
    public func invalidate() async {
        await refresher.invalidate(store: store)
    }
}
