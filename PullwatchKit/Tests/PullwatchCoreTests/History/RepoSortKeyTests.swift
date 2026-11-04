import Foundation
import PullwatchCore
import PullwatchTestSupport
import Testing

/// De kolom Repo sorteert op de naam die hij toont en binnen een repo op nummer (#193).
@Suite struct RepoSortKeyTests {
    func entry(_ repo: String, _ number: Int) -> HistoryEntry {
        .pullRequest(.fixture(repo: repo, number: number))
    }

    @Test func `Keeps a repository together and orders it by number`() {
        let entries = [
            entry("FerroHEALTH/FerroFED", 10), entry("acme/zeta", 1), entry("FerroHEALTH/FerroFED", 9),
            entry("FerroHEALTH/FerroAPI", 1570), entry("other/FerroFED", 2), entry("FerroHEALTH/FerroFED", 100),
        ]

        let sorted = entries.sorted { $0.repoSortKey < $1.repoSortKey }

        #expect(sorted.map { "\($0.repo) \($0.pullRequestNumber ?? 0)" } == [
            "FerroHEALTH/FerroAPI 1570",
            "FerroHEALTH/FerroFED 9", "FerroHEALTH/FerroFED 10", "FerroHEALTH/FerroFED 100",
            "other/FerroFED 2",
            "acme/zeta 1",
        ])
    }

    @Test func `A tag sorts by the full repository`() {
        let tag = HistoryEntry.tag(.fixture(repo: "acme/zeta", name: "v1"))
        let pr = entry("beta/alpha", 1)

        #expect(tag.repoSortKey < pr.repoSortKey, "acme/zeta voor alpha")
    }
}
