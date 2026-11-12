import SwiftUI

/// De gevolgde repo's die het token van dit account niet kan lezen (niet gevonden of geen
/// toegang), met wat eraan te doen is. Bij `gh` zonder gekozen login komt het token van het
/// actieve account in `gh`; wisselen daar kan zo een organisatie onbereikbaar maken.
struct UnreachableReposSection: View {
    let repos: [String]
    /// Het token komt van het actieve account in `gh` (GitHub, `gh`, geen login gekozen).
    let followsActiveGhAccount: Bool

    var body: some View {
        Section {
            ForEach(repos, id: \.self) { repo in
                Label {
                    Text(verbatim: repo).lineLimit(1).truncationMode(.middle)
                } icon: {
                    Image(systemName: "lock.slash").foregroundStyle(.secondary)
                }
            }
        } header: {
            Label {
                Text("Niet te lezen met dit token")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pullwatch kan deze gevolgde repositories niet lezen: niet gevonden of geen toegang. Hun tags en branches komen niet binnen tot de toegang terug is.")
                if followsActiveGhAccount {
                    Text("Het token komt van het actieve account in gh. Kies bij GitHub-account de login die deze repositories kan lezen.")
                } else {
                    Text("Geef het token toegang tot deze repositories, of volg ze niet meer.")
                }
            }
        }
        .accessibilityIdentifier("account.unreachable")
    }
}
