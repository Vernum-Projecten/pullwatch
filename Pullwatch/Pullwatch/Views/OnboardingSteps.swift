import AppKit
import PullwatchCore
import SwiftUI
import UserNotifications

/// De eerste stap van het welkomstvenster: welkom, en waar Pullwatch in de menubalk staat.
struct WelcomeStep: View {
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize = 96.0

    var body: some View {
        FitsOrScrolls {
            content
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.welcome")
    }

    private var content: some View {
        VStack(spacing: 18) {
            // Uit de eigen bundle: `applicationIconImage` geeft het icoon dat macOS voor deze
            // bundle id onthouden heeft, bijvoorbeeld van een oudere versie in Programma's.
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .accessibilityHidden(true)
            Text("Welkom bij Pullwatch")
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Pullwatch meldt nieuwe pull requests en tags uit Azure DevOps en GitHub, houdt een doorzoekbare geschiedenis bij en checkt je repo's op verouderde versies en bekende kwetsbaarheden.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
            MenuBarHint()
                .padding(.top, 8)
            Text("Pullwatch draait in de menubalk, rechtsboven naast de klok. Het heeft geen icoon in het Dock en geen venster zolang je er niets mee doet.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
            Text("Zie je het icoon niet? Bij een volle menubalk of de camera-uitsparing kan macOS het verbergen; onder Systeeminstellingen → Menubalk bepaal je welke icoontjes er staan.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
    }
}

/// De stap van het welkomstvenster waarin je een account toevoegt.
struct AccountStep: View {
    @Environment(AccountsModel.self) private var accounts
    @Binding var draft: Account?
    @Binding var enterprise: Bool
    let saveAction: AccountSaveAction
    let onAdded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Je eerste account")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 20)
                .padding(.top, 20)
            if let account = draft {
                Text(account.authMethod == .gitHubApp
                     ? "Log in met GitHub, kies waar je repositories staan en welke je volgt, en klik op Toevoegen."
                     : enterprise
                     ? "Vul je server, een token en je gebruiker of organisatie in, en klik op Toevoegen. Met de GitHub CLI heb je geen token nodig."
                     : account.kind == .gitLab
                     ? "Vul je server, een token met de scope read_api en je groepen in, en klik op Toevoegen. Met de GitLab CLI (glab auth login) heb je geen token nodig."
                     : "Vul de gegevens in en klik op Toevoegen. Met de Azure CLI (az login) heb je geen token nodig.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                AccountEditor(accounts: accounts, original: account, enterprise: enterprise, saveAction: saveAction, onSaved: onAdded)
                    .id(account.id)
            } else {
                let added = accounts.config.pollableAccounts
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
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("onboarding.addedAccounts")
                }
                Text(added.isEmpty
                     ? "Waar staan de repositories die je wilt volgen? Je kunt later meer accounts toevoegen onder Instellingen."
                     : "Nog een account toevoegen? Dat kan ook later onder Instellingen.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                HStack(spacing: 16) {
                    GitHubChoice(
                        dotCom: { start(.gitHub) },
                        enterprise: { start(.gitHub, enterprise: true) }
                    )
                    ProviderChoice(kind: .azureDevOps, detail: "Een organisatie op dev.azure.com") {
                        start(.azureDevOps)
                    }
                    .accessibilityIdentifier("onboarding.addAzureDevOps")
                    ProviderChoice(kind: .gitLab, detail: "Een groep of gebruiker op gitlab.com of je eigen GitLab-server") {
                        start(.gitLab)
                    }
                    .accessibilityIdentifier("onboarding.addGitLab")
                }
                // Alle kaarten even hoog, ook als die van GitHub twee knoppen heeft.
                .fixedSize(horizontal: false, vertical: true)
                .padding(20)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.account")
    }

    private func start(_ kind: ProviderKind, enterprise: Bool = false) {
        self.enterprise = enterprise
        // Op GitHub Enterprise bestaat de Pullwatch-app niet: daar een token.
        draft = Account(kind: kind, organization: "", authMethod: enterprise ? .pat : accounts.defaultAuthMethod(for: kind))
    }
}

/// De kaart van GitHub, met twee knoppen: github.com of GitHub Enterprise (Server of GHE.com).
private struct GitHubChoice: View {
    let dotCom: () -> Void
    let enterprise: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize = 28.0

    var body: some View {
        VStack(spacing: 8) {
            ProviderMark(kind: .gitHub, size: symbolSize)
                .frame(height: symbolSize)
            Text(verbatim: ProviderKind.gitHub.name).font(.headline)
            Text("Een gebruiker of organisatie")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // De knoppen onderaan de kaart; logo, naam en uitleg staan bovenaan, net als bij de andere kaarten.
            Spacer(minLength: 4)
            VStack(spacing: 4) {
                Button(action: dotCom) {
                    Text(verbatim: "GitHub.com").frame(maxWidth: .infinity)
                }
                .help("Een gebruiker of organisatie op github.com")
                .accessibilityIdentifier("onboarding.addGitHub")
                Button(action: enterprise) {
                    Text(verbatim: "GitHub Enterprise").frame(maxWidth: .infinity)
                }
                .help("GitHub Enterprise Server, of je eigen subdomein op ghe.com")
                .accessibilityIdentifier("onboarding.addGitHubEnterprise")
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity, alignment: .top)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator) }
        .accessibilityElement(children: .contain)
    }
}

/// Een grote kaart per dienst, bewust in dit eigen uiterlijk. Het beeld (het GitHub-logo, of een
/// SF Symbol waar de dienst geen logo toestaat) groeit mee met de tekstgrootte, en VoiceOver
/// leest titel en uitleg als een knop.
private struct ProviderChoice: View {
    let kind: ProviderKind
    let detail: LocalizedStringKey
    let action: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize = 28.0

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ProviderMark(kind: kind, size: symbolSize)
                    .frame(height: symbolSize)
                Text(verbatim: kind.name).font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Bovenaan uitgelijnd, zodat logo, naam en uitleg van alle kaarten op één lijn staan.
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity, alignment: .top)
            .padding(12)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator) }
        .help(Text(detail))
    }
}

/// De laatste stap van het welkomstvenster ("Bijna klaar"): waar je Pullwatch voortaan vindt.
struct FinishStep: View {

    var body: some View {
        FitsOrScrolls {
            content
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.finish")
    }

    private var content: some View {
        VStack(spacing: 18) {
            Text("Bijna klaar")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Form {
                Section {
                    NotificationPermissionRow()
                    LaunchAtLoginToggle()
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 540)
            MenuBarHint()
            Text("Klik voortaan op het icoon in de menubalk voor je PR's en tags, of open Pullwatch opnieuw voor het hoofdvenster.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
    }
}
