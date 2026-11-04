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

/// De stap van het welkomstvenster waarin je een account toevoegt: eerst de keuze van de dienst
/// (`ProviderPicker`), dan het formulier van het nieuwe account.
struct AccountStep: View {
    @Environment(AccountsModel.self) private var accounts
    @Binding var draft: Account?
    @Binding var enterprise: Bool
    let saveAction: AccountSaveAction
    let onAdded: () -> Void

    var body: some View {
        if let account = draft {
            VStack(alignment: .leading, spacing: 12) {
                Text("Je eerste account")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                Text(explanation(for: account))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                AccountEditor(accounts: accounts, original: account, enterprise: enterprise, saveAction: saveAction, onSaved: onAdded)
                    .id(account.id)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("onboarding.account")
        } else {
            ProviderPicker(added: accounts.config.pollableAccounts, start: start)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("onboarding.account")
        }
    }

    private func explanation(for account: Account) -> LocalizedStringKey {
        if account.authMethod == .gitHubApp {
            return "Log in met GitHub, kies waar je repositories staan en welke je volgt, en klik op Toevoegen."
        }
        switch (account.kind, enterprise) {
        case (.gitHub, true):
            return "Vul je server, een token en je gebruiker of organisatie in, en klik op Toevoegen. Met de GitHub CLI heb je geen token nodig."
        case (.gitLab, true):
            return "Vul je server, een token met de scope read_api en je groepen in, en klik op Toevoegen. Met de GitLab CLI (glab auth login) heb je geen token nodig."
        case (.gitLab, false):
            return "Vul een token met de scope read_api en je groepen in, en klik op Toevoegen. Met de GitLab CLI (glab auth login) heb je geen token nodig."
        default:
            return "Vul de gegevens in en klik op Toevoegen. Met de Azure CLI (az login) heb je geen token nodig."
        }
    }

    /// `enterprise`: een eigen server (GitHub Enterprise of een eigen GitLab-server).
    private func start(_ kind: ProviderKind, enterprise: Bool) {
        self.enterprise = enterprise
        // Op GitHub Enterprise bestaat de Pullwatch-app niet: daar een token.
        draft = Account(kind: kind, organization: "", authMethod: enterprise ? .pat : accounts.defaultAuthMethod(for: kind))
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
