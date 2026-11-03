import Foundation
import PullwatchCore

/// Het token van de GitLab CLI (`glab auth login`) voor één host, zoals `GhCLISource` voor `gh`.
/// `glab config get token --host <host>` geeft het opgeslagen token, of niets als `glab` daar
/// niet is ingelogd.
public actor GlabCLISource: TokenSource {
    private let runner: any ProcessRunner
    private let locator: CLILocator
    /// De host zoals `glab` hem kent ("gitlab.com", "gitlab.example.com").
    private let host: String
    private let now: @Sendable () -> Date
    private var cached: (token: String, fetchedAt: Date)?

    public init(
        runner: any ProcessRunner,
        locator: CLILocator = CLILocator(),
        host: String = "gitlab.com",
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.runner = runner
        self.locator = locator
        self.host = host
        self.now = now
    }

    public func token() async throws -> String {
        // Kort bewaren: `glab` ververst een OAuth-token zelf, dan willen we het nieuwe.
        if let cached, now().timeIntervalSince(cached.fetchedAt) < 15 * 60 {
            return cached.token
        }
        guard let glab = locator.locate("glab") else { throw ProviderError.cliNotFound("glab") }
        let output = try await runner.run(glab, ["config", "get", "token", "--host", host])
        let token = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.status == 0, !token.isEmpty else { throw ProviderError.cliNotLoggedIn("glab") }
        cached = (token, now())
        return token
    }

    public func invalidate() async {
        cached = nil
    }
}
