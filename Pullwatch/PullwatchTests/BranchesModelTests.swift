import Foundation
import PullwatchCore
import Testing

@testable import Pullwatch

@MainActor @Suite struct BranchesModelTests {
    let account = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func push(_ sha: String, account: UUID? = nil, age: TimeInterval = 0) -> BranchPush {
        BranchPush(
            accountId: account ?? self.account, repo: "o/r", branch: "main", newSha: sha, kind: .push,
            isOwn: false, pushedAt: now.addingTimeInterval(-age), webURL: URL(string: "https://example.com/\(sha)")!
        )
    }

    private func result(_ pushes: [BranchPush]) -> PollResult {
        var result = PollResult()
        result.branchPushes = pushes
        return result
    }

    @Test func `Apply adds the pushes of a poll`() {
        let model = BranchesModel(store: nil)
        model.apply(result([push("a"), push("b", age: 10)]), retention: .forever, now: now)

        #expect(model.log.pushes.map(\.newSha) == ["a", "b"])
    }

    @Test func `Apply prunes pushes older than the retention`() {
        let model = BranchesModel(store: nil)
        let old = push("old", age: 70 * 86_400)
        model.apply(result([push("new"), old]), retention: .twoMonths, now: now)

        #expect(model.log.pushes.map(\.newSha) == ["new"])
    }

    @Test func `Removing an account keeps the other accounts`() {
        let other = UUID()
        let model = BranchesModel(store: nil)
        model.apply(result([push("a"), push("b", account: other)]), retention: .forever, now: now)
        model.removeAccount(account)

        #expect(model.log.pushes.map(\.newSha) == ["b"])
    }

    @Test func `The log is saved and read back`() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "branches-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = JSONFileStore<BranchLog>(url: url)
        BranchesModel(store: store).apply(result([push("a")]), retention: .forever, now: now)

        #expect(BranchesModel(store: store).log.pushes.map(\.newSha) == ["a"])
    }

    @Test func `Apply does not change the unread count of the history`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "branches-\(UUID().uuidString)")
        let key = "PullwatchDataDirectory"
        let previous = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(directory.path(percentEncoded: false), forKey: key)
        defer {
            UserDefaults.standard.set(previous, forKey: key)
            try? FileManager.default.removeItem(at: directory)
        }
        let services = AppServices()
        let history = HistoryModel(services: services, accounts: AccountsModel(services: services))
        let before = history.unreadCount
        let model = BranchesModel(store: nil)
        model.apply(result([push("a")]), retention: .forever, now: now)

        #expect(history.unreadCount == before)
        #expect(model.log.pushes.count == 1)
    }
}
