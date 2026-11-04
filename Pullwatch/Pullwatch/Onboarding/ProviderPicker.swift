import PullwatchCore
import SwiftUI

/// De keuze van de dienst in het welkomstvenster: een kaart per dienst met dezelfde opbouw
/// (teken, naam, een regel uitleg en de knoppen), in rijen van hooguit drie, gecentreerd in het
/// venster zoals de andere stappen. De kaarten zijn even breed; de rijen zijn zo gelijk mogelijk
/// verdeeld (vier kaarten twee en twee, vijf drie en twee), zodat het venster in balans blijft.
struct ProviderPicker: View {
    /// De accounts die al zijn toegevoegd, boven de kaarten.
    let added: [Account]
    /// Begint een nieuw account; `enterprise` is een eigen server.
    let start: (_ kind: ProviderKind, _ enterprise: Bool) -> Void

    /// Zoveel kaarten hooguit naast elkaar; breder past niet in het welkomstvenster.
    static let maxPerRow = 3
    /// De breedte van elke kaart, zodat een kortere rij dezelfde kaarten heeft.
    private static let cardWidth: CGFloat = 196

    var body: some View {
        FitsOrScrolls {
            VStack(spacing: 18) {
                Text("Je eerste account")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if !added.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(added) { account in
                            Label {
                                Text(verbatim: account.displayName)
                            } icon: {
                                AccountAvatar(account: account, size: 22)
                            }
                        }
                    }
                    .accessibilityIdentifier("onboarding.addedAccounts")
                }
                Text(added.isEmpty
                     ? "Waar staan de repositories die je wilt volgen? Je kunt later meer accounts toevoegen onder Instellingen."
                     : "Nog een account toevoegen? Dat kan ook later onder Instellingen.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 460)
                    .fixedSize(horizontal: false, vertical: true)
                let cards = self.cards
                VStack(spacing: 16) {
                    ForEach(Self.rows(of: cards.count), id: \.lowerBound) { row in
                        HStack(spacing: 16) {
                            ForEach(cards[row], id: \.kind) { card in
                                card.frame(width: Self.cardWidth)
                            }
                        }
                        // Alle kaarten van een rij even hoog: zo hoog als de hoogste.
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(32)
        }
    }

    /// De kaarten in de volgorde van het venster.
    private var cards: [ProviderCard] {
        [
            ProviderCard(kind: .gitHub, subtitle: "Een gebruiker of organisatie", actions: [
                .init(
                    id: "onboarding.addGitHub", title: Text(verbatim: "GitHub.com"),
                    help: "Een gebruiker of organisatie op github.com",
                    accessibilityLabel: "GitHub-account toevoegen op github.com"
                ) { start(.gitHub, false) },
                .init(
                    id: "onboarding.addGitHubEnterprise", title: Text(verbatim: "GitHub Enterprise"),
                    help: "GitHub Enterprise Server, of je eigen subdomein op ghe.com",
                    accessibilityLabel: "GitHub Enterprise-account toevoegen"
                ) { start(.gitHub, true) },
            ]),
            ProviderCard(kind: .azureDevOps, subtitle: "Een organisatie", actions: [
                .init(
                    id: "onboarding.addAzureDevOps", title: Text(verbatim: "dev.azure.com"),
                    help: "Een organisatie op dev.azure.com",
                    accessibilityLabel: "Azure DevOps-account toevoegen"
                ) { start(.azureDevOps, false) },
            ]),
            ProviderCard(kind: .gitLab, subtitle: "Een groep of gebruiker", actions: [
                .init(
                    id: "onboarding.addGitLab", title: Text(verbatim: "GitLab.com"),
                    help: "Een groep of gebruiker op gitlab.com",
                    accessibilityLabel: "GitLab-account toevoegen op gitlab.com"
                ) { start(.gitLab, false) },
                .init(
                    id: "onboarding.addGitLabSelfManaged", title: Text("Eigen server"),
                    help: "Een groep of gebruiker op je eigen GitLab-server",
                    accessibilityLabel: "Account toevoegen op je eigen GitLab-server"
                ) { start(.gitLab, true) },
            ]),
            ProviderCard(kind: .bitbucket, subtitle: "Een workspace", actions: [
                .init(
                    id: "onboarding.addBitbucket", title: Text(verbatim: "bitbucket.org"),
                    help: "Een workspace op bitbucket.org (Bitbucket Cloud)",
                    accessibilityLabel: "Bitbucket-account toevoegen op bitbucket.org"
                ) { start(.bitbucket, false) },
            ]),
        ]
    }

    /// De kaarten per rij, als bereiken in de lijst: zo min mogelijk rijen van hooguit
    /// `maxPerRow`, en de langere rijen eerst (5 wordt 3 en 2, 4 wordt 2 en 2, 7 wordt 3, 2 en 2).
    static func rows(of count: Int) -> [Range<Int>] {
        guard count > 0 else { return [] }
        let rowCount = (count + maxPerRow - 1) / maxPerRow
        let base = count / rowCount
        let longer = count % rowCount
        var rows: [Range<Int>] = []
        var start = 0
        for index in 0..<rowCount {
            let length = base + (index < longer ? 1 : 0)
            rows.append(start..<(start + length))
            start += length
        }
        return rows
    }
}
