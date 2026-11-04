import AppKit
import PullwatchCore
import SwiftUI

/// Het tabblad Afhankelijkheden van de repo-pagina: de tabel met elk package per workspace.
struct RepoDependenciesTab: View {
    let versions: RepoVersions?
    @Bindable var page: RepoPage
    let width: TableWidth
    let isChecking: Bool

    var body: some View {
        if versions == nil {
            NotCheckedView(isChecking: isChecking)
        } else if !page.isBuilt {
            Color.clear
        } else if let registries = versions?.skippedVersionSources.filter(SourceOff.isRegistry), !registries.isEmpty, page.packageCount > 0 {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(registries, id: \.self) { source in
                        SourceOffText(text: SourceOff.versionNotChecked(source))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider()
                RepoPackageTableArea(page: page, width: width, skippedSources: versions?.skippedSources ?? [])
            }
        } else if page.packageCount == 0 {
            ContentUnavailableView(
                "Geen packages",
                systemImage: "shippingbox",
                description: Text("Geen packages met een vaste versie gevonden")
            )
        } else {
            RepoPackageTableArea(page: page, width: width, skippedSources: versions?.skippedSources ?? [])
        }
    }
}

/// De tabel met packages, of wat het filter overliet.
private struct RepoPackageTableArea: View {
    @Bindable var page: RepoPage
    let width: TableWidth
    let skippedSources: Set<DataSourceID>

    var body: some View {
        RepoPackageTable(page: page, width: width, skippedSources: skippedSources)
            .id(width)
            .overlay {
                if page.visiblePackageGroups.isEmpty {
                    FilteredEmptyView(searchText: page.searchText) {
                        page.packageFilter = PackageFilter()
                        page.searchText = ""
                    }
                }
            }
    }
}
