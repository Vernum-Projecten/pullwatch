import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct VersionHistoryTests {
    let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    private func report(at date: Date) -> VersionReport {
        let go = ComponentVersion(product: "go", label: "Go", version: "1.27.3", latest: "1.27.4", status: .current, sources: ["go.mod"],
                                  cycle: "1.27", cycleLatest: "1.27.4")
        let high = Vulnerability(id: "GHSA-1", cve: nil, summary: nil, severity: "HIGH", ecosystem: "Go", package: "x",
                                 version: "1.0.0", fixedIn: nil, source: "go.mod")
        return VersionReport(checkedAt: date, repos: [
            RepoVersions(accountId: fixedAccountId, repo: "P/api", components: [go], vulnerabilities: [high, high]),
            RepoVersions(accountId: fixedAccountId, repo: "Werk", components: [], error: "Token ongeldig"),
        ])
    }

    @Test func snapshotKeepsVersionsStatusesAndCounts() {
        var history = VersionHistory()
        history.append(report(at: t0))
        let snapshot = history.snapshots.first
        #expect(snapshot?.checkedAt == t0)
        #expect(snapshot?.repos.map(\.id) == ["\(fixedAccountId.uuidString)/P/api"])
        let repo = snapshot?.repos.first
        #expect(repo?.components == ["Go": "1.27.3"])
        #expect(repo?.statuses == ["Go": .current])
        #expect(repo?.vulnerabilities == ["HIGH": 2])
        #expect(repo?.packageUpdates == 1)
    }

    @Test func keepsAtMostMaxSnapshotsDroppingTheOldest() {
        var history = VersionHistory()
        for day in 0..<(VersionHistory.maxSnapshots + 3) {
            history.append(VersionReport(checkedAt: t0 + Double(day) * 86_400, repos: []))
        }
        #expect(history.snapshots.count == VersionHistory.maxSnapshots)
        #expect(history.snapshots.first?.checkedAt == t0 + 3 * 86_400)
    }

    @Test func roundTrips() throws {
        var history = VersionHistory()
        history.append(report(at: t0))
        let decoded = try JSONDecoder().decode(VersionHistory.self, from: JSONEncoder().encode(history))
        #expect(decoded == history)
    }
}
