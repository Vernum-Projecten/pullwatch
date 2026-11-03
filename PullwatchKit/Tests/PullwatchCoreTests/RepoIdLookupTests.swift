import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct RepoIdLookupTests {
    let report = VersionReport(checkedAt: Date(timeIntervalSince1970: 0), repos: [
        RepoVersions(accountId: fixedAccountId, repo: "Proj/Api", components: []),
    ])

    @Test func `A history name finds the summary whatever its case`() {
        let summaries = RepoOverview.summaries(accounts: [], report: report, history: History())
        #expect(RepoOverview.repoId(in: summaries, accountId: fixedAccountId, repo: "proj/api") == "\(fixedAccountId.uuidString)/Proj/Api")
    }

    @Test func `Without a summary the id is built from the name`() {
        #expect(RepoOverview.repoId(in: [], accountId: fixedAccountId, repo: "proj/web") == "\(fixedAccountId.uuidString)/proj/web")
    }
}
