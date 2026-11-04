import Foundation
import PullwatchCore
@testable import PullwatchGitHub
import PullwatchTestSupport

/// Een provider voor github.com die eigenaar `owner` volgt, met een vast token en `http`.
func makeProvider(_ http: MockHTTPClient, owner: String = "acme") -> GitHubProvider {
    GitHubProvider(accountId: fixedAccountId, owner: owner, tokenSource: StaticTokenSource(token: "ghtok"), http: http)
}
