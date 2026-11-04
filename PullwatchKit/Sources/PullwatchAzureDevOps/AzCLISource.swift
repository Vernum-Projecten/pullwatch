public import Foundation
public import PullwatchCore

/// Het token van de Azure CLI (`az account get-access-token`) voor Azure DevOps.
public actor AzCLISource: TokenSource {
    private static let devOpsResource = "499b84ac-1321-427f-aa17-267ca6975798"

    private let runner: any ProcessRunner
    private let locator: CLILocator
    private let now: @Sendable () -> Date
    private var cached: (token: String, expiresAt: Date)?

    public init(runner: any ProcessRunner, locator: CLILocator = CLILocator(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.runner = runner
        self.locator = locator
        self.now = now
    }

    public func token() async throws -> String {
        if let cached, cached.expiresAt.addingTimeInterval(-300) > now() {
            return cached.token
        }
        guard let az = locator.locate("az") else { throw ProviderError.cliNotFound("az") }
        let output = try await runner.run(az, ["account", "get-access-token", "--resource", Self.devOpsResource, "--output", "json"])
        guard output.status == 0 else { throw ProviderError.cliNotLoggedIn("az") }

        struct Response: Decodable {
            let accessToken: String
            let expires_on: Int?
        }
        let response = try JSONDecoding.decode(Response.self, from: Data(output.stdout.utf8))
        let expiresAt = response.expires_on.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            ?? now().addingTimeInterval(3000)
        cached = (response.accessToken, expiresAt)
        return response.accessToken
    }

    public func invalidate() async {
        cached = nil
    }
}
