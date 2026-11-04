import PullwatchCore
import SwiftUI

/// De kolom Repo van de lijst: bij een PR de korte naam van de repo met het nummer erachter
/// (`FerroFED #1570`), bij een tag de repo voluit. Het nummer is ingetogen zoals de telling van
/// de checks (`ChecksBadge`): secundair en met cijfers van gelijke breedte. De tooltip geeft de
/// verwijzing voluit (`FerroHEALTH/FerroFED#1570`); VoiceOver leest "pull request 1570" in plaats
/// van het teken. Leest zelf geen model uit de environment (zie `ChecksBadge`).
struct RepoReferenceLabel: View {
    let entry: HistoryEntry
    /// De dienst van het account, voor het teken (`#` of `!`).
    let kind: ProviderKind

    var body: some View {
        switch entry {
        case .pullRequest(let pr):
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: PullRequest.shortName(of: pr.repo))
                    .lineLimit(1)
                Text(verbatim: pr.numberText(kind))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .help(pr.reference(kind))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(PullRequestNumberText.spoken(repo: PullRequest.shortName(of: pr.repo), number: pr.number))
        case .tag(let tag):
            Text(verbatim: tag.repo)
                .lineLimit(1)
                .help(tag.repo)
        }
    }
}
