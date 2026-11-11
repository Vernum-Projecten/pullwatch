import Foundation
import Testing
import PullwatchTestSupport
@testable import PullwatchCore

/// Branches volgen per repo: standaard aan met de PR's, zonder eigen melding.
@Suite struct BranchWatchTests {
    @Test func oldJSONFollowsBranchesWhenItFollowsPRs() throws {
        let set = try JSONDecoder().decode(WatchSet.self, from: Data(#"{"prs":true,"tags":false}"#.utf8))
        #expect(set.branches)
        let tagsOnly = try JSONDecoder().decode(WatchSet.self, from: Data(#"{"prs":false,"tags":true}"#.utf8))
        #expect(!tagsOnly.branches)
    }

    @Test func storedBranchesChoiceWinsOverPRs() throws {
        let set = try JSONDecoder().decode(WatchSet.self, from: Data(#"{"prs":true,"tags":false,"branches":false}"#.utf8))
        #expect(!set.branches)
        let decoded = try JSONDecoder().decode(WatchSet.self, from: JSONEncoder().encode(WatchSet.prs))
        #expect(decoded == .prs)
    }

    @Test func newRepoDefaultsFollowBranchesWithPRs() {
        #expect(NewRepoDefault.prs.watchSet.branches)
        #expect(NewRepoDefault.prsAndTags.watchSet.branches)
        #expect(!NewRepoDefault.none.watchSet.branches)
        #expect(!WatchSet.tags.branches)
    }

    @Test func followingBranchesIsItsOwnSwitch() {
        var set = WatchSet.none
        set[follows: .branches] = true
        #expect(set.branches && !set.prs && !set.tags)
        #expect(set[follows: .branches])
        set[follows: .branches] = false
        #expect(!set.branches)
    }

    @Test func branchesHaveNoNotification() {
        var set = WatchSet.prs
        set[notifies: .branches] = true
        #expect(!set[notifies: .branches])
        set[notifies: .branches] = false
        #expect(!set[notifies: .branches])
    }

    @Test func setWatchToDefaultStoresNoEntry() {
        var account = Account.fixture(repoWatch: [:])
        account.setWatch(.prs, for: "proj/a")
        #expect(account.repoWatch["proj/a"] == nil)
    }

    @Test func branchReposFollowDefaultFromAvailable() {
        let account = Account.fixture(repoWatch: ["proj/off": .none, "proj/tags": .tags], newRepoDefault: .prs)
        #expect(account.followsBranchesByDefault)
        #expect(account.branchRepos(available: ["proj/a", "proj/off", "proj/tags", "Proj/B"]) == ["proj/a", "Proj/B"])
        #expect(!Account.fixture(newRepoDefault: .none).followsBranchesByDefault)
    }

    @Test func branchReposListsExplicitOnesOnce() {
        var onlyBranches = WatchSet.none
        onlyBranches.branches = true
        let account = Account.fixture(
            repoWatch: ["proj/b": onlyBranches, "Proj/B": onlyBranches, "proj/a": .prs, "proj/t": .tags], newRepoDefault: .none
        )
        #expect(account.branchRepos == ["Proj/B", "proj/a"])
    }

    @Test func followingOnlyBranchesCountsAsFollowing() {
        var onlyBranches = WatchSet.none
        onlyBranches.branches = true
        #expect(Account.fixture(repoWatch: ["proj/a": onlyBranches], newRepoDefault: .none).followsAnything)
        #expect(!Account.fixture(repoWatch: ["proj/a": .none], newRepoDefault: .none).followsAnything)
    }

    @Test func sameSyncScopeIgnoresBranchFlags() {
        var withoutBranches = WatchSet.prs
        withoutBranches.branches = false
        let a = Account.fixture(repoWatch: ["proj/a": .prs])
        var b = a
        b.repoWatch["proj/a"] = withoutBranches
        #expect(a.filterSettings.sameSyncScope(as: b.filterSettings))
    }
}
