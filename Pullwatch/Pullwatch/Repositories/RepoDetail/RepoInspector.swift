import AppKit
import PullwatchCore
import SwiftUI

/// Het inspectievenster rechts op de repo-pagina: de details van de gekozen rij van het tabblad.
struct RepoInspector: View {
    @Environment(VersionsModel.self) private var versions
    @Environment(AppRouter.self) private var router
    let summary: RepoSummary
    let page: RepoPage
    let tab: RepoTab

    var body: some View {
        VStack(spacing: 0) {
            switch tab {
            case .check:
                if let selected = page.selectedVulnerability {
                    AdvisoryInspector(
                        row: selected.row,
                        install: selected.install,
                        releaseTag: page.summary?.comparedWith,
                        showsWorkspace: page.vulnerabilitiesSpanWorkspaces,
                        showPackage: versions.packageSummaries.contains { $0.label == selected.row.package } ? { router.showPackage($0) } : nil
                    )
                } else {
                    NoSelectionView(text: Text("Kies een kwetsbaarheid om de details te zien."))
                }
            case .dependencies:
                if let selected = page.selectedPackage {
                    PackageInspector(
                        row: selected,
                        showsWorkspace: page.packagesSpanWorkspaces,
                        skippedRegistry: DataSourceID.registry(ecosystem: selected.row.package.ecosystem)
                            .flatMap { summary.versions?.isUnchecked($0) == true ? $0 : nil },
                        showPackage: versions.packageSummaries.contains { $0.id == selected.row.package.id } ? { router.showPackage($0) } : nil
                    )
                } else {
                    NoSelectionView(text: Text("Kies een package om de details te zien."))
                }
            case .security:
                if let selected = page.selectedSecurityFinding {
                    SecurityFindingInspector(row: selected)
                } else {
                    NoSelectionView(text: Text("Kies een melding om de details te zien."))
                }
            case .overview:
                EmptyView()
            }
        }
    }
}

/// Wat het inspectievenster toont zolang er geen rij gekozen is.
private struct NoSelectionView: View {
    let text: Text

    var body: some View {
        ContentUnavailableView {
            Label("Niets gekozen", systemImage: "sidebar.trailing")
        } description: {
            text
        }
    }
}
