#if DEBUG
import AppKit
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
        // `-PullwatchSnapshotDark YES`: de schermen in donkere modus, los van de instelling van de Mac.
        if UserDefaults.standard.bool(forKey: "PullwatchSnapshotDark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        // Eerst de lege schermen tijdens de eerste sync, met de balk onderin (met
        // `-PullwatchFakeDelay` duurt die lang genoeg om te zien).
        if model.history.items.isEmpty {
            model.show(.pullRequests)
            try? await Task.sleep(for: .seconds(2))
            SnapshotCamera.shoot("fetching-pull-requests", windowId: WindowID.main.rawValue)
            // De camera wacht zelf 400 ms; pas daarna verder.
            try? await Task.sleep(for: .seconds(1))
            model.show(.tags)
            try? await Task.sleep(for: .seconds(1))
            SnapshotCamera.shoot("fetching-tags", windowId: WindowID.main.rawValue)
            try? await Task.sleep(for: .seconds(1))
            model.show(.repos)
            try? await Task.sleep(for: .seconds(1))
            SnapshotCamera.shoot("fetching-repos", windowId: WindowID.main.rawValue)
            try? await Task.sleep(for: .seconds(1))
            // De versiecheck met zijn aantallen, zodra die loopt.
            for _ in 0..<120 where model.versionCheck.map({ $0.total == 0 }) ?? true {
                try? await Task.sleep(for: .milliseconds(250))
            }
            model.show(.dependencies)
            try? await Task.sleep(for: .seconds(1))
            SnapshotCamera.shoot("checking-versions", windowId: WindowID.main.rawValue)
            try? await Task.sleep(for: .seconds(1))
        }
        for _ in 0..<240 where model.history.items.isEmpty || model.versionReport == nil || model.versionCheck != nil {
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
            ("versions", { model.show(.dependencies) }),
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
            // Wat onder de vouw staat: controle, kwetsbaarheden en packages.
            for page in 1...4 {
                steps.append(("repo-detail-\(page + 1)", { SnapshotCamera.scroll(windowId: WindowID.main.rawValue, pages: Double(page)) }))
            }
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
