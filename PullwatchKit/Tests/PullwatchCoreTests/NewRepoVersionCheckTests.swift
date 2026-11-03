import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct NewRepoVersionCheckTests {
    let account = Account.fixture(id: fixedAccountId, repoWatch: ["proj/api": .init(prs: true, tags: false)], newRepoDefault: .none)
    let report = VersionReport(checkedAt: Date(timeIntervalSince1970: 0), repos: [
        RepoVersions(accountId: fixedAccountId, repo: "proj/Known", components: []),
    ])

    @Test func `Repo key ignores case`() {
        #expect(Account.repoKey(accountId: fixedAccountId, repo: "Proj/API") == "\(fixedAccountId.uuidString)/proj/api")
    }

    @Test func `A followed repo that is not in the report is unseen`() {
        let result = PollResult(newPullRequests: [.fixture(repo: "proj/api")])
        #expect(NewRepoVersionCheck.hasUnseenRepo(in: result, accounts: [account], report: report, attempted: []))
    }

    @Test func `A repo already in the report is not unseen, whatever its case`() {
        let followed = Account.fixture(id: fixedAccountId, repoWatch: ["proj/known": .init(prs: true, tags: false)])
        let result = PollResult(syncedPullRequests: [.fixture(repo: "proj/known")])
        #expect(!NewRepoVersionCheck.hasUnseenRepo(in: result, accounts: [followed], report: report, attempted: []))
    }

    @Test func `A repo checked once already is not unseen`() {
        let result = PollResult(newPullRequests: [.fixture(repo: "proj/api")])
        let attempted: Set = [Account.repoKey(accountId: fixedAccountId, repo: "proj/api")]
        #expect(!NewRepoVersionCheck.hasUnseenRepo(in: result, accounts: [account], report: report, attempted: attempted))
    }

    @Test func `A repo that is not followed is not unseen`() {
        let result = PollResult(tagRepos: [fixedAccountId: ["proj/other"]])
        #expect(!NewRepoVersionCheck.hasUnseenRepo(in: result, accounts: [account], report: report, attempted: []))
    }

    @Test func `A repo of an account that is gone is not unseen`() {
        let result = PollResult(syncedTags: [.fixture(accountId: UUID(), repo: "proj/api")])
        #expect(!NewRepoVersionCheck.hasUnseenRepo(in: result, accounts: [account], report: report, attempted: []))
    }

    @Test func `A changed follow scope needs a check without new repos`() {
        let result = PollResult()
        #expect(NewRepoVersionCheck.isNeeded(after: result, accounts: [account], report: report, attempted: [], lastScope: nil))
        let scope = NewRepoVersionCheck.scope(of: [account])
        #expect(!NewRepoVersionCheck.isNeeded(after: result, accounts: [account], report: report, attempted: [], lastScope: scope))
    }

    @Test func `The same scope with an unseen repo needs a check`() {
        let result = PollResult(newPullRequests: [.fixture(repo: "proj/api")])
        let scope = NewRepoVersionCheck.scope(of: [account])
        #expect(NewRepoVersionCheck.isNeeded(after: result, accounts: [account], report: report, attempted: [], lastScope: scope))
    }
}
