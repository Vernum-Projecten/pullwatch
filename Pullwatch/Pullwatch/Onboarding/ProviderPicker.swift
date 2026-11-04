import PullwatchCore
import SwiftUI

/// De keuze van de dienst in het welkomstvenster: drie kaarten met dezelfde opbouw (teken, naam,
/// een regel uitleg en de knoppen), gecentreerd in het venster zoals de andere stappen.
struct ProviderPicker: View {
    /// De accounts die al zijn toegevoegd, boven de kaarten.
    let added: [Account]
    /// Begint een nieuw account; `enterprise` is een eigen server.
    let start: (_ kind: ProviderKind, _ enterprise: Bool) -> Void

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
                HStack(spacing: 16) {
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
                    ])
                    ProviderCard(kind: .azureDevOps, subtitle: "Een organisatie", actions: [
                        .init(
                            id: "onboarding.addAzureDevOps", title: Text(verbatim: "dev.azure.com"),
                            help: "Een organisatie op dev.azure.com",
                            accessibilityLabel: "Azure DevOps-account toevoegen"
                        ) { start(.azureDevOps, false) },
                    ])
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
                    ])
                }
                // Alle kaarten even hoog: zo hoog als de hoogste.
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(32)
        }
    }
}
