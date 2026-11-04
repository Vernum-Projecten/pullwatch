import AppKit
import PullwatchCore
import SwiftUI

/// Runtimes en frameworks als raster, meldingen over wat niet te checken was, en de
/// kwetsbaarheden als tabel.
struct RepoCheckTab: View {
    let versions: RepoVersions?
    let page: RepoPage
    let width: TableWidth
    let isChecking: Bool
    /// De GitHub Advisory Database staat uit: de details van GitHub zijn niet opgehaald.
    let advisoryDetailsOff: Bool
    let openAdvisory: (VulnerabilityRow) -> Void

    var body: some View {
        if let versions {
            if let error = versions.error {
                ContentUnavailableView("Check mislukt", systemImage: "exclamationmark.triangle", description: Text(verbatim: error))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    RepoComponentsArea(
                        versions: versions, onlyOutdated: page.onlyOutdatedComponents, outdated: page.outdatedComponents,
                        advisoryDetailsOff: advisoryDetailsOff
                    )
                    Divider()
                    RepoVulnerabilitiesArea(versions: versions, page: page, width: width, openAdvisory: openAdvisory)
                }
            }
        } else {
            NotCheckedView(isChecking: isChecking)
        }
    }
}

/// Het raster met talen en frameworks, en wat er niet te checken was.
private struct RepoComponentsArea: View {
    let versions: RepoVersions
    let onlyOutdated: Bool
    let outdated: [ComponentVersion]
    let advisoryDetailsOff: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if versions.components.isEmpty {
                Text("Geen talen of frameworks herkend").foregroundStyle(.secondary)
            } else {
                ComponentGrid(
                    components: onlyOutdated ? outdated : versions.components, release: versions.release,
                    skippedSources: versions.skippedSources
                )
            }
            // Een releasebron die uit stond: de onderdelen hebben dan geen status, en hier waarom.
            ForEach(versions.skippedVersionSources.filter { !SourceOff.isRegistry($0) }, id: \.self) { source in
                SourceOffText(text: SourceOff.notChecked(source))
            }
            // OSV.dev uit staat onder het raster, waar anders de kwetsbaarheden staan.
            if advisoryDetailsOff, !versions.vulnerabilities.isEmpty {
                SourceOffText(text: SourceOff.detailsNotFetched(.gitHubAdvisoryDatabase))
            }
            if let release = versions.release, let error = release.error {
                CheckNotice(text: Text("Tag \(release.tag) niet te checken: \(error)", comment: "Tagnaam, foutmelding"))
            }
            if let vulnerabilityError = versions.vulnerabilityError {
                CheckNotice(text: Text(verbatim: vulnerabilityError))
            }
            if !versions.withdrawnVulnerabilities.isEmpty {
                WithdrawnAdvisoriesNote(vulnerabilities: versions.withdrawnVulnerabilities)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// Een melding over wat niet te checken was.
private struct CheckNotice: View {
    let text: Text

    var body: some View {
        Label {
            text.fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}

/// De tabel met kwetsbaarheden van het tabblad Controle, of wat er staat als die leeg is.
private struct RepoVulnerabilitiesArea: View {
    let versions: RepoVersions
    @Bindable var page: RepoPage
    let width: TableWidth
    let openAdvisory: (VulnerabilityRow) -> Void

    var body: some View {
        if !page.isBuilt {
            // De rijen worden nog opgebouwd (een fractie van een seconde); geen lege staat tonen.
            Color.clear
        } else if versions.isUnchecked(.osv) {
            // Met OSV.dev uit nooit "Geen bekende kwetsbaarheden": er is niets gecontroleerd.
            ContentUnavailableView(
                "Niet gecontroleerd",
                systemImage: "slash.circle",
                description: Text(verbatim: SourceOff.notChecked(.osv))
            )
        } else if page.vulnerabilityCount == 0 {
            ContentUnavailableView(
                "Geen bekende kwetsbaarheden",
                systemImage: "checkmark.shield",
                description: Text("OSV.dev kent geen lekken in de packages van deze repo.")
            )
        } else {
            // Een andere breedte is een nieuwe tabel: de kolommen beginnen dan weer op hun ideale breedte.
            VulnerabilityTable(page: page, releaseTag: page.summary?.comparedWith, width: width, openAdvisory: openAdvisory)
                .id(width)
                .overlay {
                    if page.visibleVulnerabilities.isEmpty {
                        FilteredEmptyView(searchText: page.searchText) {
                            page.vulnerabilityFilter = VulnerabilityFilter()
                            page.searchText = ""
                        }
                    }
                }
        }
    }
}

/// Een repo zonder versiecheck: nog niet gecheckt, of de check loopt.
struct NotCheckedView: View {
    let isChecking: Bool

    var body: some View {
        // De voortgang staat in de balk onderin; hier alleen wat er gebeurt.
        ContentUnavailableView(
            isChecking ? "Repo checken…" : "Nog niet gecheckt",
            systemImage: "checkmark.shield",
            description: Text("Check deze repo om de runtimes, packages en kwetsbaarheden te zien.")
        )
    }
}
