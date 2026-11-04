import Foundation
import Testing
@testable import PullwatchCore
@testable import PullwatchGitLab
import PullwatchTestSupport

@Suite struct GlabCLISourceTests {
    let homebrew = CLILocator.homebrew

    @Test func asksTheTokenForTheHostAndCaches() async throws {
        let runner = MockProcessRunner()
        runner.output = ProcessOutput(status: 0, stdout: "glpat-abc\n", stderr: "")
        let source = GlabCLISource(runner: runner, locator: homebrew, host: "gitlab.example.com")
        #expect(try await source.token() == "glpat-abc")
        #expect(try await source.token() == "glpat-abc")
        #expect(runner.calls.count == 1)
        #expect(runner.calls.first?.0.path == "/opt/homebrew/bin/glab")
        #expect(runner.calls.first?.1 == ["config", "get", "token", "--host", "gitlab.example.com"])
    }

    @Test func emptyOutputMeansNotLoggedIn() async {
        let runner = MockProcessRunner()
        runner.output = ProcessOutput(status: 0, stdout: "\n", stderr: "")
        let source = GlabCLISource(runner: runner, locator: homebrew)
        await #expect(throws: ProviderError.cliNotLoggedIn("glab")) { try await source.token() }
        #expect(ProviderError.cliNotLoggedIn("glab").userMessage.contains("glab auth login"))
    }

    @Test func missingGlabIsReported() async {
        let source = GlabCLISource(runner: MockProcessRunner(), locator: .nothing)
        await #expect(throws: ProviderError.cliNotFound("glab")) { try await source.token() }
    }

    @Test func invalidateAsksAgain() async throws {
        let runner = MockProcessRunner()
        runner.output = ProcessOutput(status: 0, stdout: "one", stderr: "")
        let source = GlabCLISource(runner: runner, locator: homebrew)
        _ = try await source.token()
        await source.invalidate()
        _ = try await source.token()
        #expect(runner.calls.count == 2)
    }
}
