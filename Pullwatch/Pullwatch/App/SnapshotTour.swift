#if DEBUG
import AppKit
import PullwatchCore

/// Alleen in debug-builds, met `-PullwatchSnapshotTour YES` (en `-PullwatchSnapshotDirectory`):
/// loopt eenmalig langs elk scherm van het hoofdvenster en bewaart elk als PNG, zodat de schermen
/// te bekijken zijn zonder UI-automatisering. Wacht tot er geschiedenis en een versiecheck zijn,
/// bv. met `-PullwatchFakeGitHub YES -PullwatchFakeData YES`.
enum SnapshotTour {
    private static var hasRun = false

    static func runIfRequested(_ model: AppModel) async {
        guard UserDefaults.standard.bool(forKey: "PullwatchSnapshotTour"), !hasRun else { return }
        hasRun = true
        // `-PullwatchSnapshotDark YES`: de schermen in donkere modus, los van de instelling van de Mac.
        if UserDefaults.standard.bool(forKey: "PullwatchSnapshotDark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else if UserDefaults.standard.bool(forKey: "PullwatchSnapshotLight") {
            // `-PullwatchSnapshotLight YES`: lichte modus, ook als de Mac donker staat.
            NSApp.appearance = NSAppearance(named: .aqua)
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
        // `-PullwatchSnapshotSmallest YES`: het hoofdvenster op zijn kleinste maat, om afkappen te zien.
        if UserDefaults.standard.bool(forKey: "PullwatchSnapshotSmallest"),
           let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(WindowID.main.rawValue) == true }) {
            window.setContentSize(NSSize(width: max(window.contentMinSize.width, 900), height: max(window.contentMinSize.height, 520)))
            try? await Task.sleep(for: .seconds(1))
        }
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
                model.repoTab = .overview
                model.showRepo(id: repo.id)
            }))
            // De controle: runtimes en kwetsbaarheden, en een gekozen advies in het inspectievenster.
            steps.append(("repo-check", { model.repoSelectionRequest = RepoSelectionRequest(tab: .check) }))
            if let advisory = repo.versions?.vulnerabilityRows(gitHub: repo.advisories).max(by: { $0.severity < $1.severity }) {
                steps.append(("repo-check-inspector", { model.repoSelectionRequest = RepoSelectionRequest(tab: .check, rowId: advisory.id) }))
            }
            // Packages, met een package dat iets tegenhoudt in het inspectievenster.
            steps.append(("repo-packages", { model.repoSelectionRequest = RepoSelectionRequest(tab: .packages) }))
            steps.append(("repo-packages-inspector", { model.repoSelectionRequest = RepoSelectionRequest(tab: .packages, rowId: "|npm:express") }))
            // De beveiliging van GitHub zelf, met een melding van code scanning.
            steps.append(("repo-security", { model.repoSelectionRequest = RepoSelectionRequest(tab: .security) }))
            if let alert = repo.versions?.security?.findingRows.first {
                steps.append(("repo-security-inspector", { model.repoSelectionRequest = RepoSelectionRequest(tab: .security, rowId: alert.id) }))
            }
            // Een repo met een eigen advies bij "Beveiliging op GitHub".
            if let linguist = model.repoSummaries.first(where: { $0.repo.hasSuffix("/linguist") && $0.id != repo.id }) {
                steps.append(("repo-detail-linguist", {
                    model.showRepo(id: linguist.id)
                    model.repoSelectionRequest = RepoSelectionRequest(tab: .security)
                }))
                steps.append(("repo-detail-linguist-2", { model.repoSelectionRequest = RepoSelectionRequest(tab: .check) }))
                steps.append(("repo-detail-back", {
                    model.showRepo(id: repo.id)
                    model.repoSelectionRequest = RepoSelectionRequest(tab: .overview)
                }))
            }
            steps.append(("repo-stats", { model.showStats(repoId: repo.id) }))
            steps.append(("repo-history-token", { model.showHistory(.pullRequest, repo: HistoryRepo(accountId: repo.accountId, repo: repo.repo)) }))
        }
        // Een losse repo van een andere organisatie (de nep-openEHR) in de lijst van Repo's.
        if let extra = model.repoSummaries.first(where: { $0.repo.hasPrefix("openEHR/") }) {
            steps.append(("repo-detail-extra", {
                model.show(.repos)
                model.showRepo(id: extra.id)
            }))
        }
        steps.append(("repos-again", { model.show(.repos) }))
        for (name, step) in steps {
            step()
            try? await Task.sleep(for: .seconds(1.5))
            SnapshotCamera.shoot(name, windowId: WindowID.main.rawValue)
            try? await Task.sleep(for: .seconds(0.8))
        }
        // "Volg een repository…": het blad fotografeert zichzelf ("watch-repository").
        model.watchRepository()
        try? await Task.sleep(for: .seconds(2))
        model.isWatchingRepository = false
        try? await Task.sleep(for: .seconds(1))
        // De lijst van het account in Instellingen, met "Andere repositories" onderaan.
        model.show(.settings)
        try? await Task.sleep(for: .seconds(3))
        let settings = "com_apple_SwiftUI_Settings_window"
        for page in 1...6 {
            SnapshotCamera.scroll(windowId: settings, pages: Double(page))
            try? await Task.sleep(for: .seconds(0.6))
            SnapshotCamera.shoot("settings-repos-\(page)", windowId: settings)
            try? await Task.sleep(for: .seconds(0.8))
        }
    }
}
#endif
