import Foundation
import Testing
@testable import PullwatchCore
@testable import PullwatchGitHub
import PullwatchTestSupport

@Suite struct ProviderFileTests {
    @Test func gitHubListsBlobsAndTreatsEmptyRepoAsNoFiles() async throws {
        let http = MockHTTPClient()
        http.on("repos/acme/empty/git/trees", status: 409, body: "{}")
        http.on("repos/acme/web/git/trees/HEAD", body: #"{"tree":[{"path":"src","type":"tree"},{"path":"src/go.mod","type":"blob"}],"truncated":false}"#)
        let provider = GitHubProvider(accountId: fixedAccountId, owner: "acme", tokenSource: StaticTokenSource(token: "t"), http: http)

        #expect(try await provider.filePaths(in: "acme/web") == ["src/go.mod"])
        #expect(try await provider.filePaths(in: "acme/empty") == [])
        #expect(http.requests.first?.url?.query == "recursive=1")
    }

    @Test func gitHubReadsRawContent() async throws {
        let http = MockHTTPClient()
        http.on("repos/acme/web/contents/src/go.mod", body: "go 1.26\n")
        let provider = GitHubProvider(accountId: fixedAccountId, owner: "acme", tokenSource: StaticTokenSource(token: "t"), http: http)

        #expect(try await provider.fileContent(in: "acme/web", path: "src/go.mod") == "go 1.26\n")
        #expect(http.requests.first?.value(forHTTPHeaderField: "Accept") == "application/vnd.github.raw+json")
    }

    @Test func gitHubReadsTreeAndContentOnTag() async throws {
        let http = MockHTTPClient()
        http.on("git/trees/v1.2.0", body: #"{"tree":[{"path":"go.mod","type":"blob"}]}"#)
        http.on("contents/go.mod", body: "go 1.26\n")
        let provider = GitHubProvider(accountId: fixedAccountId, owner: "acme", tokenSource: StaticTokenSource(token: "t"), http: http)

        #expect(try await provider.filePaths(in: "acme/web", ref: "v1.2.0") == ["go.mod"])
        #expect(try await provider.fileContent(in: "acme/web", path: "go.mod", ref: "v1.2.0") == "go 1.26\n")
        #expect(http.requests.last?.url?.query == "ref=v1.2.0")
    }
}
