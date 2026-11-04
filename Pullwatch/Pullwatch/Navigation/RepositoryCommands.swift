import PullwatchCore
import SwiftUI

/// Het menu Repository: de gekozen repository checken, alles checken, de statistieken, de
/// afhankelijkheden kopiëren, en de geschiedenis opnieuw ophalen of het ophalen stoppen.
struct RepositoryCommands: Commands {
    let model: AppModel
    @FocusedValue(\.repoTarget) private var repoTarget

    private var summary: RepoSummary? {
        repoTarget.flatMap { model.overview.repoSummariesById[$0.id] }
    }

    /// Een check van alle repo's of van één repo loopt.
    private var isChecking: Bool {
        model.versions.versionCheck != nil || !model.versions.refreshingRepos.isEmpty
    }

    var body: some Commands {
        CommandMenu("Repository") {
            Button("Check repository") {
                if let summary { model.versions.startRefresh(of: summary) }
            }
            .disabled(summary == nil || isChecking || model.versions.versionReport == nil)
            Button("Alle repo's checken") { model.versions.startCheck() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(isChecking)
            Divider()
            Button("Statistieken van repository") {
                if let repoTarget { model.router.showStats(repoId: repoTarget.id) }
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(repoTarget?.isOpen != true)
            Button("Kopieer afhankelijkheden voor agent") {
                guard let summary, let text = summary.versions?.clipboardText(
                    advisories: summary.advisories, report: model.versions.versionReport,
                    advisoryDetailsOff: !model.accounts.config.isEnabled(.gitHubAdvisoryDatabase)
                ) else { return }
                Pasteboard.copy(text)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(repoTarget?.isOpen != true || summary?.versions == nil)
            Divider()
            Button("Geschiedenis opnieuw ophalen") { model.polling.startRefetch() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.polling.refetch != nil)
            Button("Ophalen stoppen") { model.cancelSync() }
                .keyboardShortcut(".")
                .disabled(!(model.syncStatus.work?.isCancellable ?? false))
        }
    }
}
