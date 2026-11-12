import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct SeenStateTests {
    let t0 = Date.testStart
    let day: TimeInterval = 24 * 3600

    @Test func markThenContains() {
        var state = SeenState()
        #expect(!state.contains("a"))
        state.mark("a", at: t0)
        #expect(state.contains("a"))
    }

    @Test func pruneRemovesEntriesOlderThan30Days() {
        var state = SeenState()
        state.mark("old", at: t0)
        state.mark("recent", at: t0 + 25 * day)
        state.prune(now: t0 + 31 * day)
        #expect(!state.contains("old"))
        #expect(state.contains("recent"))
    }

    @Test func markRefreshesTimestampSoPruneKeepsIt() {
        var state = SeenState()
        state.mark("a", at: t0)
        state.mark("a", at: t0 + 20 * day)
        state.prune(now: t0 + 40 * day)
        #expect(state.contains("a"))
    }

    @Test func roundTripsThroughJSONFileStore() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileStore<SeenState>(url: dir.appending(path: "seen.json"))

        var state = SeenState()
        state.mark("a", at: t0)
        state.lastSettings["acc"] = Account.fixture(repoWatch: ["p/r": .none]).filterSettings
        try store.save(state)

        #expect(try store.load() == state)
    }

    @Test func prefixScopedPruneAndRetain() {
        var state = SeenState()
        state.mark("a:x", at: t0)
        state.mark("b:x", at: t0)
        state.prune(now: t0 + 31 * 24 * 3600, onlyKeyPrefixes: ["a:"])
        #expect(!state.contains("a:x"))
        #expect(state.contains("b:x"))
        state.retain(onlyKeyPrefixes: ["a:"])
        #expect(state.seen.isEmpty)
    }

    @Test func pruneAlsoDropsStaleTagSeeded() {
        var state = SeenState()
        state.tagSeeded["a:old"] = t0
        state.tagSeeded["a:recent"] = t0 + 25 * day
        state.tagSeeded["b:old"] = t0
        state.prune(now: t0 + 31 * day, onlyKeyPrefixes: ["a:"])
        #expect(state.tagSeeded.keys.sorted() == ["a:recent", "b:old"])
        state.prune(now: t0 + 31 * day)
        #expect(state.tagSeeded.keys.sorted() == ["a:recent"])
    }

    @Test func tagSeededRoundTrips() throws {
        var state = SeenState()
        state.tagSeeded["a:proj/x"] = t0
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(SeenState.self, from: data) == state)
    }

    @Test func legacySeenJsonLoads() throws {
        let json = Data(#"{"seen":{},"lastSettings":{}}"#.utf8)
        let state = try JSONDecoder().decode(SeenState.self, from: json)
        #expect(state.tagSeeded.isEmpty)
        #expect(state.seen.isEmpty)
    }

    @Test func legacySeenJsonWithoutSyncMarksLoads() throws {
        let json = Data(#"{"seen":{},"lastSettings":{},"tagSeeded":{}}"#.utf8)
        let state = try JSONDecoder().decode(SeenState.self, from: json)
        #expect(state.syncMarks.isEmpty)
    }

    @Test func syncMarksRoundTrip() throws {
        var state = SeenState()
        state.syncMarks["acc"] = SyncMark(
            at: t0,
            settings: Account.fixture(repoWatch: ["p/r": .none]).filterSettings,
            retention: .sixMonths
        )
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(SeenState.self, from: data) == state)
    }

    @Test func legacySeenJsonWithoutBranchHeadsLoads() throws {
        let json = Data(#"{"seen":{},"lastSettings":{}}"#.utf8)
        let state = try JSONDecoder().decode(SeenState.self, from: json)
        #expect(state.branchHeads.isEmpty)
    }

    @Test func branchHeadsRoundTripAndPrune() throws {
        var state = SeenState()
        state.branchHeads["a:p/r"] = BranchHeads(heads: ["main": "abc"], fingerprint: "f", seenAt: t0)
        state.branchHeads["a:p/new"] = BranchHeads(heads: ["main": "def"], fingerprint: nil, seenAt: t0 + 30 * day)
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(SeenState.self, from: data) == state)
        state.prune(now: t0 + 31 * day)
        #expect(state.branchHeads.keys.sorted() == ["a:p/new"])
    }

    @Test func prefixScopedPruneAndRetainCoverBranchHeads() {
        var state = SeenState()
        state.branchHeads["a:x"] = BranchHeads(heads: [:], fingerprint: nil, seenAt: t0)
        state.branchHeads["b:x"] = BranchHeads(heads: [:], fingerprint: nil, seenAt: t0)
        state.prune(now: t0 + 31 * day, onlyKeyPrefixes: ["a:"])
        #expect(state.branchHeads.keys.sorted() == ["b:x"])
        state.branchHeads["a:y"] = BranchHeads(heads: [:], fingerprint: nil, seenAt: t0)
        state.retain(onlyKeyPrefixes: ["a:"])
        #expect(state.branchHeads.keys.sorted() == ["a:y"])
    }
}
