import Foundation
import Testing
import PullwatchTestSupport
@testable import PullwatchCore

/// Branches volgen per repo: standaard aan met de PR's, zonder eigen melding.
@Suite struct BranchWatchTests {
    /// Zoals een vinkje in de accounteditor (en "alle" per eigenaar, dat elke repo zo zet): lezen,
    /// via `WatchSet[follows:]` wijzigen, terugschrijven.
    private func follow(_ account: inout Account, _ repo: String, _ on: Bool, _ kind: WatchKind = .pullRequests) {
        var watch = account.watch(for: repo)
        watch[follows: kind] = on
        account.setWatch(watch, for: repo)
    }

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
        var withoutBranches = WatchSet.prs
        withoutBranches.branches = false
        account.setWatch(withoutBranches, for: "proj/a")
        #expect(account.repoWatch["proj/a"] == withoutBranches)
    }

    @Test func `Turning PRs on also follows branches`() {
        var set = WatchSet.none
        set[follows: .pullRequests] = true
        #expect(set.prs && set.branches)
    }

    @Test func `Turning PRs off also stops branches`() {
        var set = WatchSet.prs
        set[follows: .pullRequests] = false
        #expect(!set.prs && !set.branches)
    }

    @Test func `Turning merged on follows branches with the PRs`() {
        var set = WatchSet.none
        set[follows: .merged] = true
        #expect(set.prs && set.branches)
    }

    @Test func `Ticking PRs on a repo of a none account follows its branches`() {
        var account = Account.fixture(repoWatch: [:], newRepoDefault: .none)
        follow(&account, "proj/a", true)
        #expect(account.watch(for: "proj/a").branches)
        #expect(account.branchRepos == ["proj/a"])
        follow(&account, "proj/a", false)
        #expect(!account.watch(for: "proj/a").branches)
        #expect(account.branchRepos.isEmpty)
    }

    @Test func `Unticking PRs on a repo of a prs account stops its branches`() {
        var account = Account.fixture(repoWatch: [:], newRepoDefault: .prs)
        follow(&account, "proj/a", false)
        #expect(!account.watch(for: "proj/a").branches)
        follow(&account, "proj/a", true)
        #expect(account.watch(for: "proj/a") == .prs)
        #expect(account.repoWatch["proj/a"] == nil)
    }

    @Test func `Following all PRs of an owner follows all their branches`() {
        var account = Account.fixture(repoWatch: [:], newRepoDefault: .none)
        for repo in ["proj/a", "proj/b"] { follow(&account, repo, true) }
        #expect(account.branchRepos.sorted() == ["proj/a", "proj/b"])
    }

    @Test func `The branches switch stays its own after PRs`() {
        var set = WatchSet.prs
        set[follows: .branches] = false
        #expect(set.prs && !set.branches)
        set[follows: .tags] = true
        #expect(!set.branches)
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
