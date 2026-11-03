#if DEBUG
import Foundation
import PullwatchCore

/// Alleen in debug-builds, met `-PullwatchSnapshotTour YES` (en `-PullwatchSnapshotDirectory`):
/// loopt eenmalig langs elk scherm van het hoofdvenster en bewaart elk als PNG, zodat de schermen
/// te bekijken zijn zonder UI-automatisering. Wacht tot er geschiedenis en een versiecheck zijn,
/// bv. met `-PullwatchFakeGitHub YES -PullwatchFakeData YES`.
@MainActor
enum SnapshotTour {
    private static var hasRun = false

    static func runIfRequested(_ model: AppModel) async {
        guard UserDefaults.standard.bool(forKey: "PullwatchSnapshotTour"), !hasRun else { return }
        hasRun = true
        for _ in 0..<120 where model.history.items.isEmpty || model.versionReport == nil || model.versionCheck != nil {
            try? await Task.sleep(for: .milliseconds(500))
        }
        model.show(.main)
        try? await Task.sleep(for: .seconds(2))
        let repo = model.repoSummaries.first { $0.repo.hasSuffix("hello-world") } ?? model.repoSummaries.first
        let group = model.sidebar.pullRequestGroups.first

        var steps: [(String, () -> Void)] = [
            ("pull-requests", { model.show(.pullRequests) }),
            ("tags", { model.show(.tags) }),
            ("stats", { model.show(.stats) }),
            ("repos", { model.show(.repos) }),
            ("versions", { model.show(.versions) }),
            ("history-author-token", { model.showHistory(.pullRequest, author: "mona") }),
        ]
        if let group {
            steps.append(("history-group", { model.sidebarSelection = .group(.pullRequest, group.id) }))
        }
        if let repo {
            steps.append(("repo-detail", {
                model.show(.repos)
                model.showRepo(id: repo.id)
            }))
            steps.append(("repo-stats", { model.showStats(repoId: repo.id) }))
            steps.append(("repo-history-token", { model.showHistory(.pullRequest, repo: HistoryRepo(accountId: repo.accountId, repo: repo.repo)) }))
        }
        for (name, step) in steps {
            step()
            try? await Task.sleep(for: .seconds(1.5))
            SnapshotCamera.shoot(name, windowId: WindowID.main.rawValue)
            try? await Task.sleep(for: .seconds(0.8))
        }
    }
}
#endif
