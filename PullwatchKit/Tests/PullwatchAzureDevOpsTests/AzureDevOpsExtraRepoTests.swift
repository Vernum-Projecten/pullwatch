import Foundation
import Testing
@testable import PullwatchAzureDevOps
@testable import PullwatchCore
import PullwatchTestSupport

/// Een losse repo (`project/repo`) binnen de organisatie van een Azure DevOps-account.
@Suite struct AzureDevOpsExtraRepoTests {
    func makeProvider(_ http: MockHTTPClient) -> AzureDevOpsProvider {
        AzureDevOpsProvider(
            accountId: fixedAccountId, organization: "acme", tokenSource: StaticTokenSource(token: "secret"),
            authMethod: .pat, http: http
        )
    }

    @Test func checksTheRepositoryWithOneRequest() async throws {
        let http = MockHTTPClient()
        http.on("_apis/git/repositories/web", body: #"{"name":"Web","project":{"name":"My Project"}}"#)

        let check = try await makeProvider(http).checkRepository("my project/web")

        #expect(check == RepositoryCheck(name: "My Project/Web"))
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.url?.absoluteString.contains("dev.azure.com/acme/my%20project/_apis/git/repositories/web") == true)
    }

    @Test func missingRepositoryIsNoAccess() async throws {
        let http = MockHTTPClient()
        http.on("_apis/git/repositories/nope", status: 404, body: #"{"message":"TF401019"}"#)

        await #expect(throws: ProviderError.noAccess("Website/nope")) {
            try await makeProvider(http).checkRepository("Website/nope")
        }
    }
}
