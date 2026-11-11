import AppKit
import Observation
import PullwatchCore

nonisolated private let logger = Log(category: "app")

/// De pushes naar branches (branches.json), apart van de geschiedenis van PR's en tags: ze tellen
/// niet mee als ongelezen en geven geen melding.
@Observable
final class BranchesModel {
    private(set) var log: BranchLog

    @ObservationIgnored private let store: JSONFileStore<BranchLog>?

    /// `nil` houdt alles in het geheugen (tests).
    init(store: JSONFileStore<BranchLog>?) {
        self.store = store
        var initial = BranchLog()
        do {
            initial = try store?.load() ?? BranchLog()
        } catch {
            logger.error("branches onleesbaar, start leeg: \(error.localizedDescription)")
        }
        log = initial
    }

    /// Voegt de pushes van een poll toe, snoeit op de bewaartermijn en bewaart het resultaat.
    func apply(_ result: PollResult, retention: HistoryRetention, now: Date) {
        var updated = log
        updated.add(result.branchPushes)
        updated.prune(now: now, retention: retention)
        guard updated != log else { return }
        log = updated
        save()
    }

    /// Na een kortere bewaartermijn in Instellingen.
    func prune(retention: HistoryRetention, now: Date = Date()) {
        var updated = log
        updated.prune(now: now, retention: retention)
        guard updated != log else { return }
        log = updated
        save()
    }

    func removeAccount(_ id: UUID) {
        var updated = log
        updated.removeAccount(id)
        guard updated != log else { return }
        log = updated
        save()
    }

    func open(_ push: BranchPush) {
        NSWorkspace.shared.open(push.webURL)
    }

    private func save() {
        guard let store else { return }
        do {
            try store.save(log)
        } catch {
            logger.error("branches opslaan mislukt: \(error.localizedDescription)")
        }
    }
}
