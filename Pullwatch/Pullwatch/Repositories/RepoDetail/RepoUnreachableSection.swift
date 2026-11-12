import SwiftUI

/// Bovenaan het Overzicht van een repo die het token van zijn account niet kan lezen: de tags
/// en branches op de pagina zijn dan van vóór de toegang wegviel. De knop opent het account in
/// Instellingen, waar staat wat eraan te doen is.
struct RepoUnreachableSection: View {
    let accountName: String
    let openAccount: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("Niet te lezen met het token van \(accountName)", comment: "De naam van het account, zoals ‘cadasto op GitHub’")
                        .fontWeight(.medium)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                }
                Text("Niet gevonden of geen toegang. Nieuwe tags en branches komen niet binnen tot de toegang terug is.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Account openen", action: openAccount)
                    .accessibilityIdentifier("repo.unreachable.openAccount")
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("repo.unreachable")
    }
}
