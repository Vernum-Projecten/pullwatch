import Foundation
import PullwatchCore
import PullwatchTestSupport
import Testing

@Suite struct BranchLogTests {
    @Test func addSortsNewestFirstAndIgnoresDuplicates() {
        var log = BranchLog()
        let old = BranchPush.fixture(branch: "a", newSha: "1", pushedAt: .testStart)
        let new = BranchPush.fixture(branch: "b", newSha: "2", pushedAt: .testStart.addingTimeInterval(60))
        log.add([old]); log.add([new, old])
        #expect(log.pushes.map(\.branch) == ["b", "a"])
    }

    @Test func pruneDropsPushesOlderThanRetention() {
        var log = BranchLog(pushes: [.fixture(pushedAt: .testStart)])
        let changed = log.prune(now: .testStart.addingTimeInterval(62 * 86_400), retention: .twoMonths)
        #expect(changed)
        #expect(log.pushes.isEmpty)
    }

    @Test func pruneForeverKeepsAll() {
        var log = BranchLog(pushes: [.fixture(pushedAt: .testStart)])
        let changed = log.prune(now: .testStart.addingTimeInterval(5_000 * 86_400), retention: .forever)
        #expect(!changed)
        #expect(log.pushes.count == 1)
    }

    @Test func removeAccountDropsOnlyThatAccount() {
        let other = UUID()
        var log = BranchLog(pushes: [.fixture(newSha: "1"), .fixture(accountId: other, newSha: "2")])
        log.removeAccount(other)
        #expect(log.pushes.map(\.newSha) == ["1"])
    }

    @Test func decodesWhatItEncodes() throws {
        let kinds: [BranchPush.Kind] = [.push, .forcePush, .newBranch, .recent]
        let pushes = kinds.enumerated().map { index, kind in
            BranchPush.fixture(oldSha: "o", newSha: "n\(index)", commits: index, kind: kind)
        }
        let log = BranchLog(pushes: pushes)
        let data = try JSONEncoder().encode(log)
        #expect(try JSONDecoder().decode(BranchLog.self, from: data) == log)
    }
}
