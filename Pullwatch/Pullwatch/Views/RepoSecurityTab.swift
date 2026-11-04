import AppKit
import PullwatchCore
import SwiftUI

/// Het tabblad Beveiliging van de repo-pagina: de meldingen van de dienst zelf.
struct RepoSecurityTab: View {
    let scan: SecurityScan?
    /// De beveiligingsbron van de dienst stond uit (Instellingen, Bronnen).
    let skipped: DataSourceID?
    @Bindable var page: RepoPage
    let provider: ProviderKind
    let width: TableWidth

    init(scan: SecurityScan?, skipped: DataSourceID?, provider: ProviderKind, page: RepoPage, width: TableWidth) {
        self.scan = scan
        self.skipped = skipped
        self.provider = provider
        self.page = page
        self.width = width
    }

    var body: some View {
        if let scan {
            VStack(alignment: .leading, spacing: 0) {
                SecurityFeedGrid(scan: scan, provider: provider)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider()
                if !page.isBuilt {
                    Color.clear
                } else if page.securityCount == 0 {
                    ContentUnavailableView(
                        "Geen open meldingen",
                        systemImage: "checkmark.shield",
                        description: provider == .gitHub
                            ? Text("Code scanning en de eigen adviezen van deze repository melden niets.")
                            : Text("Advanced Security meldt niets voor deze repository.")
                    )
                } else {
                    SecurityFindingTable(page: page, width: width)
                        .id(width)
                        .overlay {
                            if page.visibleSecurity.isEmpty {
                                ContentUnavailableView.search(text: page.searchText)
                            }
                        }
                }
            }
        } else if let skipped {
            // Nooit "geen meldingen" als er niets gevraagd is.
            ContentUnavailableView(
                "Niet gecontroleerd",
                systemImage: "slash.circle",
                description: Text(verbatim: SourceOff.notChecked(skipped))
            )
        } else {
            ContentUnavailableView(
                "Geen beveiligingsgegevens",
                systemImage: "lock.shield",
                description: Text("De dienst geeft voor deze repository geen code scanning, geheimen of eigen adviezen.")
            )
        }
    }
}
