import Foundation
import PullwatchCore

public actor GhCLISource: TokenSource {
    private let runner: any ProcessRunner
    private let locator: CLILocator
    /// Login van het `gh`-account; nil = het actieve account.
    private let user: String?
    /// De server ("github.example.com", "acme.ghe.com"); nil of "github.com" = github.com.
    private let host: String?
    private let now: @Sendable () -> Date
    private var cached: (token: String, fetchedAt: Date)?

    public init(
        runner: any ProcessRunner,
        locator: CLILocator = CLILocator(),
        user: String? = nil,
        host: String? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.runner = runner
        self.locator = locator
        self.user = user
        self.host = host
        self.now = now
    }

    /// `gh auth token`, met `--hostname` voor een GitHub Enterprise-server; voor github.com
    /// precies als altijd (gh kiest dan zelf github.com, of `GH_HOST`).
    var arguments: [String] {
        var arguments = ["auth", "token"]
        if let host, host != "github.com" { arguments += ["--hostname", host] }
        if let user { arguments += ["--user", user] }
        return arguments
    }

    public func token() async throws -> String {
        if let cached, now().timeIntervalSince(cached.fetchedAt) < 15 * 60 {
            return cached.token
        }
        guard let gh = locator.locate("gh") else { throw ProviderError.cliNotFound("gh") }
        let output = try await runner.run(gh, arguments)
        let token = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.status == 0, !token.isEmpty else { throw ProviderError.cliNotLoggedIn("gh") }
        cached = (token, now())
        return token
    }

    public func invalidate() async {
        cached = nil
    }
}

/// De accounts waarmee `gh` op een host is ingelogd (github.com, of een GitHub Enterprise-server),
/// het actieve eerst.
public enum GhCLIAccounts {
    public static func list(
        runner: any ProcessRunner, locator: CLILocator = CLILocator(), host: String = "github.com"
    ) async -> [String] {
        guard let gh = locator.locate("gh"),
              let output = try? await runner.run(gh, ["auth", "status", "--json", "hosts"]) else { return [] }
        return parse(output.stdout, host: host)
    }

    static func parse(_ json: String, host: String = "github.com") -> [String] {
        struct Status: Decodable {
            struct Entry: Decodable { let login: String; let active: Bool? }
            let hosts: [String: [Entry]]
        }
        guard let status = try? JSONDecoder().decode(Status.self, from: Data(json.utf8)) else { return [] }
        // gh bewaart hosts in kleine letters; een getypte host kan anders zijn.
        let entries = status.hosts.first { $0.key.lowercased() == host.lowercased() }?.value ?? []
        return entries.filter { $0.active == true }.map(\.login) + entries.filter { $0.active != true }.map(\.login)
    }
}
