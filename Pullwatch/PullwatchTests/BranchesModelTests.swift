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

    @Test func `Apply adds the pushes of a poll`() {
        let model = BranchesModel(store: nil)
        model.apply([push("a"), push("b", age: 10)], retention: .forever, now: now)

        #expect(model.log.pushes.map(\.newSha) == ["a", "b"])
    }

    @Test func `Apply prunes pushes older than the retention`() {
        let model = BranchesModel(store: nil)
        let old = push("old", age: 70 * 86_400)
        model.apply([push("new"), old], retention: .twoMonths, now: now)

        #expect(model.log.pushes.map(\.newSha) == ["new"])
    }

    @Test func `Removing an account keeps the other accounts`() {
        let other = UUID()
        let model = BranchesModel(store: nil)
        model.apply([push("a"), push("b", account: other)], retention: .forever, now: now)
        model.removeAccount(account)

        #expect(model.log.pushes.map(\.newSha) == ["b"])
    }

    @Test func `The log is saved and read back`() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "branches-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = JSONFileStore<BranchLog>(url: url)
        BranchesModel(store: store).apply([push("a")], retention: .forever, now: now)

        #expect(BranchesModel(store: store).log.pushes.map(\.newSha) == ["a"])
    }

    /// Pushes staan in branches.json in de datamap, los van de geschiedenis: history.json blijft
    /// onaangeroerd en het aantal ongelezen verandert niet.
    @Test func `Pushes go to branches.json and leave the history alone`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "branches-\(UUID().uuidString)")
        let suite = "BranchesModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(directory.path(percentEncoded: false), forKey: "PullwatchDataDirectory")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let services = AppServices(defaults: defaults)
        let history = HistoryModel(services: services, accounts: AccountsModel(services: services))
        let before = history.unreadCount
        let model = BranchesModel(store: services.branchStore)

        model.apply([push("a")], retention: .forever, now: now)

        #expect(history.unreadCount == before)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "branches.json").path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "history.json").path(percentEncoded: false)))
        #expect(BranchesModel(store: services.branchStore).log.pushes.map(\.newSha) == ["a"])
    }
}
