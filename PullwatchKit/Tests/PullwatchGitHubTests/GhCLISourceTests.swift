import Foundation
import Testing
@testable import PullwatchCore
@testable import PullwatchGitHub
import PullwatchTestSupport

@Suite struct GhCLISourceTests {
    let homebrew = CLILocator(isExecutable: { $0.hasPrefix("/opt/homebrew/bin/") })

    @Test func ghTrimsTokenAndCaches() async throws {
        let runner = MockProcessRunner()
        runner.output = ProcessOutput(status: 0, stdout: "gho_abc\n", stderr: "")
        let source = GhCLISource(runner: runner, locator: homebrew)
        #expect(try await source.token() == "gho_abc")
        #expect(try await source.token() == "gho_abc")
        #expect(runner.calls.count == 1)
        #expect(runner.calls.first?.1 == ["auth", "token"])
    }

    @Test func ghEmptyOutputMeansNotLoggedIn() async {
        let runner = MockProcessRunner()
        runner.output = ProcessOutput(status: 0, stdout: "\n", stderr: "")
        let source = GhCLISource(runner: runner, locator: homebrew)
        await #expect(throws: ProviderError.cliNotLoggedIn("gh")) { try await source.token() }
    }

    @Test func ghAsksTokenForChosenUser() async throws {
        let runner = MockProcessRunner()
        runner.output = ProcessOutput(status: 0, stdout: "gho_x\n", stderr: "")
        _ = try await GhCLISource(runner: runner, locator: homebrew, user: "second").token()
        #expect(runner.calls.first?.1 == ["auth", "token", "--user", "second"])
    }

    @Test func ghAsksTokenForTheEnterpriseHost() async throws {
        let runner = MockProcessRunner()
        runner.output = ProcessOutput(status: 0, stdout: "gho_x\n", stderr: "")
        _ = try await GhCLISource(runner: runner, locator: homebrew, user: "me", host: "ghe.example.com").token()
        #expect(runner.calls.first?.1 == ["auth", "token", "--hostname", "ghe.example.com", "--user", "me"])

        // github.com blijft precies zoals het was.
        let dotCom = MockProcessRunner()
        dotCom.output = ProcessOutput(status: 0, stdout: "gho_x\n", stderr: "")
        _ = try await GhCLISource(runner: dotCom, locator: homebrew, host: "github.com").token()
        #expect(dotCom.calls.first?.1 == ["auth", "token"])
    }

    @Test func listsGhAccountsOfAHost() {
        let json = #"{"hosts":{"github.com":[{"login":"me","active":true}],"ghe.example.com":[{"login":"x","active":false},{"login":"y","active":true}]}}"#
        #expect(GhCLIAccounts.parse(json, host: "ghe.example.com") == ["y", "x"])
        #expect(GhCLIAccounts.parse(json, host: "GHE.example.com") == ["y", "x"])
        #expect(GhCLIAccounts.parse(json, host: "other.example.com").isEmpty)
    }

    @Test func listsGhAccountsActiveFirst() {
        let json = #"{"hosts":{"github.com":[{"login":"work","active":false},{"login":"me","active":true}],"ghe.example.com":[{"login":"x","active":true}]}}"#
        #expect(GhCLIAccounts.parse(json) == ["me", "work"])
        #expect(GhCLIAccounts.parse("not json").isEmpty)
    }
}
