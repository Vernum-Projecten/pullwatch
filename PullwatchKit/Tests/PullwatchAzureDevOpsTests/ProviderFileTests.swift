import Foundation
import Testing
@testable import PullwatchAzureDevOps
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct ProviderFileTests {
    @Test func azureListsFilesAndReadsContent() async throws {
        let http = MockHTTPClient()
        http.on("includeContent=true", body: #"{"path":"/src/go.mod","content":"go 1.26"}"#)
        http.on("Proj/_apis/git/repositories/web/items", body: #"{"value":[{"path":"/","isFolder":true},{"path":"/src/go.mod"}]}"#)
        let provider = AzureDevOpsProvider(
            accountId: fixedAccountId, organization: "org", tokenSource: StaticTokenSource(token: "t"), authMethod: .pat, http: http
        )

        #expect(try await provider.filePaths(in: "Proj/web") == ["src/go.mod"])
        #expect(try await provider.fileContent(in: "Proj/web", path: "src/go.mod") == "go 1.26")
        let query = http.requests.last?.url?.query ?? ""
        #expect(query.contains("path=/src/go.mod"))
        #expect(!query.contains("versionDescriptor"))
    }

    @Test func azureReadsOnTag() async throws {
        let http = MockHTTPClient()
        http.on("includeContent=true", body: #"{"path":"/go.mod","content":"go 1.26"}"#)
        let provider = AzureDevOpsProvider(
            accountId: fixedAccountId, organization: "org", tokenSource: StaticTokenSource(token: "t"), authMethod: .pat, http: http
        )

        _ = try await provider.fileContent(in: "Proj/web", path: "go.mod", ref: "v1.2.0")
        let query = http.requests.last?.url?.query ?? ""
        #expect(query.contains("versionDescriptor.version=v1.2.0"))
        #expect(query.contains("versionDescriptor.versionType=tag"))
    }
}
