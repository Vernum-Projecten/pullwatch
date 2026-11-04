import Foundation
@testable import PullwatchAzureDevOps
import PullwatchCore
import PullwatchTestSupport

/// Een provider voor organisatie "acme" met een vast token en `http`.
func makeProvider(_ http: MockHTTPClient, auth: AuthMethod = .pat, token: String = "secret") -> AzureDevOpsProvider {
    AzureDevOpsProvider(
        accountId: fixedAccountId,
        organization: "acme",
        tokenSource: StaticTokenSource(token: token),
        authMethod: auth,
        http: http
    )
}
