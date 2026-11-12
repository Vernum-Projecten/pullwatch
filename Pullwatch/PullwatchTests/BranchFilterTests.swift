import Foundation
import PullwatchCore
import Testing

@testable import Pullwatch

/// Het filter van het onderdeel Branches: zoeken, alleen anderen, repo en persoon.
@Suite struct BranchFilterTests {
    let account = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func push(
        _ branch: String, repo: String = "octo/app", author: String? = "mona", isOwn: Bool = false
    ) -> BranchPush {
        BranchPush(
            accountId: account, repo: repo, branch: branch, newSha: "\(repo)/\(branch)", kind: .push,
            authorName: author, isOwn: isOwn, pushedAt: now, webURL: URL(string: "https://example.com/\(branch)")!
        )
    }

    @Test func `Without a filter every push stays, in the same order`() {
        let pushes = [push("main"), push("feature/login"), push("fix/crash")]
        #expect(BranchFilter().apply(pushes) == pushes)
    }

    @Test func `Search finds part of the branch name, ignoring case`() {
        let pushes = [push("main"), push("feature/Login-Page"), push("fix/crash")]
        let filter = BranchFilter(searchText: "login")
        #expect(filter.apply(pushes).map(\.branch) == ["feature/Login-Page"])
    }

    @Test func `Search also looks in the repo and the author`() {
        let pushes = [push("a", repo: "octo/api"), push("b", author: "Hubot"), push("c")]
        #expect(BranchFilter(searchText: "API").apply(pushes).map(\.branch) == ["a"])
        #expect(BranchFilter(searchText: "hubot").apply(pushes).map(\.branch) == ["b"])
    }

    @Test func `Search with only spaces filters nothing`() {
        let pushes = [push("main"), push("dev")]
        #expect(BranchFilter(searchText: "  ").apply(pushes) == pushes)
    }

    @Test func `Others only hides own pushes`() {
        let pushes = [push("mine", isOwn: true), push("theirs")]
        #expect(BranchFilter(othersOnly: true).apply(pushes).map(\.branch) == ["theirs"])
        #expect(BranchFilter(othersOnly: false).apply(pushes).count == 2)
    }

    @Test func `Repo and author filter together`() {
        let pushes = [
            push("a", repo: "octo/app", author: "mona"),
            push("b", repo: "octo/app", author: "hubot"),
            push("c", repo: "octo/api", author: "mona"),
            push("d", repo: "octo/api", author: nil),
        ]
        let filter = BranchFilter(repo: "octo/app", author: "mona")
        #expect(filter.apply(pushes).map(\.branch) == ["a"])
        #expect(BranchFilter(repo: "OCTO/API").apply(pushes).map(\.branch) == ["c", "d"])
        #expect(BranchFilter(author: "mona").apply(pushes).map(\.branch) == ["a", "c"])
    }

    @Test func `Is filtering only with a filter set`() {
        #expect(!BranchFilter().isFiltering)
        #expect(!BranchFilter(searchText: " ").isFiltering)
        #expect(BranchFilter(searchText: "x").isFiltering)
        #expect(BranchFilter(repo: "octo/app").isFiltering)
        #expect(BranchFilter(author: "mona").isFiltering)
        #expect(BranchFilter(othersOnly: true).isFiltering)
    }
}
