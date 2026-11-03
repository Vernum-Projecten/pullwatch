import AppKit
import PullwatchCore
import SwiftUI
import UserNotifications

/// Welkomstvenster bij de eerste start. Pullwatch heeft geen Dock-icoon en geen venster, dus
/// zonder dit lijkt de app na het openen niet te starten. Drie stappen: wat Pullwatch doet en
/// waar het icoon staat, het eerste account, en meldingen en starten bij inloggen.
struct OnboardingView: View {
    let model: AppModel

    enum Step { case welcome, account, finish }

    @State private var step = Step.welcome
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: WelcomeStep()
                case .account: AccountStep(model: model)
                case .finish: FinishStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer.padding(16)
        }
        .frame(minWidth: 640, minHeight: 600)
        #if DEBUG
        .onAppear { SnapshotCamera.shoot("onboarding-welcome", windowId: "onboarding") }
        .onChange(of: step) { _, step in SnapshotCamera.shoot("onboarding-\(step)", windowId: "onboarding") }
        .onChange(of: model.config.accounts.count) { _, _ in SnapshotCamera.shoot("onboarding-account-editor", windowId: "onboarding") }
        #endif
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Terug") { step = step == .finish ? .account : .welcome }
                    .accessibilityIdentifier("onboarding.back")
            }
            Spacer()
            switch step {
            case .welcome:
                Button("Aan de slag") { step = .account }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.start")
            case .account:
                if model.config.pollableAccounts.isEmpty {
                    Button("Later instellen") { step = .finish }
                        .accessibilityIdentifier("onboarding.skip")
                } else {
                    Button("Volgende") { step = .finish }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("onboarding.next")
                }
            case .finish:
                Button("Klaar") { finish() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.done")
            }
        }
    }

    private func finish() {
        // Een half ingevuld account (zonder organisatie) blijft niet hangen.
        for account in model.config.accounts where !model.config.pollableAccounts.contains(where: { $0.id == account.id }) {
            model.removeAccount(account.id)
        }
        model.completeOnboarding()
        dismissWindow(id: "onboarding")
        if !model.config.pollableAccounts.isEmpty { model.openMainWindow?() }
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("Welkom bij Pullwatch")
                .font(.largeTitle.weight(.semibold))
            Text("Pullwatch meldt nieuwe pull requests en tags uit Azure DevOps en GitHub, houdt een doorzoekbare geschiedenis bij en checkt je repo's op verouderde versies en bekende kwetsbaarheden.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
            MenuBarHint()
                .padding(.top, 8)
            Text("Pullwatch draait in de menubalk, rechtsboven naast de klok. Het heeft geen icoon in het Dock en geen venster zolang je er niets mee doet.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Text("Zie je het icoon niet? Bij een volle menubalk of de camera-uitsparing kan macOS het verbergen; onder Systeeminstellingen → Menubalk bepaal je welke icoontjes er staan.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
        }
        .padding(32)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.welcome")
    }
}

/// Een nagetekende menubalk met het Pullwatch-icoon gemarkeerd, zodat je weet waar je moet kijken.
struct MenuBarHint: View {
    var body: some View {
        HStack(spacing: 14) {
            Spacer()
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 15, weight: .semibold))
                .padding(6)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                .accessibilityLabel(Text("Pullwatch-icoon"))
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Image(systemName: "switch.2")
            Text(Date.now, format: .dateTime.weekday(.abbreviated).hour().minute())
                .monospacedDigit()
        }
        .font(.system(size: 13))
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(width: 420, height: 34)
        .background(.bar, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        .accessibilityElement(children: .contain)
    }
}

private struct AccountStep: View {
    let model: AppModel
    @State private var accountId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Je eerste account")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 20)
            if let account = currentAccount {
                Text(account.authMethod == .gitHubApp
                     ? "Log in met GitHub, installeer Pullwatch waar je repositories staan, kies welke je volgt en klik op Opslaan."
                     : "Vul de gegevens in en klik op Opslaan. Met de GitHub CLI (gh auth login) of de Azure CLI (az login) heb je geen token nodig.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                AccountEditor(model: model, original: account).id(account.id)
            } else {
                Text("Waar staan de repositories die je wilt volgen? Je kunt later meer accounts toevoegen onder Instellingen.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                HStack(spacing: 16) {
                    ProviderChoice(title: "GitHub", detail: "Een gebruiker of organisatie op github.com", symbol: "chevron.left.forwardslash.chevron.right") {
                        add(.gitHub)
                    }
                    .accessibilityIdentifier("onboarding.addGitHub")
                    ProviderChoice(title: "Azure DevOps", detail: "Een organisatie op dev.azure.com", symbol: "cloud") {
                        add(.azureDevOps)
                    }
                    .accessibilityIdentifier("onboarding.addAzureDevOps")
                }
                .padding(20)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.account")
    }

    /// Het account dat hier wordt ingesteld, of een al bestaand account.
    private var currentAccount: Account? {
        let accounts = model.config.accounts
        return accounts.first { $0.id == accountId } ?? accounts.first
    }

    private func add(_ kind: ProviderKind) {
        let account = Account(
            kind: kind,
            displayName: kind == .azureDevOps ? "Azure DevOps" : "GitHub",
            organization: "",
            authMethod: model.defaultAuthMethod(for: kind)
        )
        model.saveAccount(account, pat: nil)
        accountId = account.id
    }
}

private struct ProviderChoice: View {
    let title: String
    let detail: LocalizedStringKey
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 28))
                Text(verbatim: title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(12)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }
}

private struct FinishStep: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Text("Bijna klaar")
                .font(.title2.weight(.semibold))
            Form {
                Section {
                    NotificationPermissionRow(model: model)
                    LaunchAtLoginToggle()
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 520, maxHeight: 220)
            MenuBarHint()
            Text("Klik voortaan op het icoon in de menubalk voor je PR's en tags, of open Pullwatch opnieuw voor het hoofdvenster.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
        }
        .padding(32)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.finish")
    }
}

/// Meldingen zoals macOS-apps het doen: de vraag van macOS komt vanzelf zodra deze stap
/// verschijnt, de rij wacht op het antwoord, en bij "Niet toestaan" (of eerder uitgezet) opent
/// een knop de meldingsinstellingen van Pullwatch. Terug uit Systeeminstellingen ziet de rij
/// de nieuwe stand vanzelf.
struct NotificationPermissionRow: View {
    let model: AppModel
    @State private var status: UNAuthorizationStatus?
    @State private var asking = false

    /// UI-tests slaan de vraag over: die zou een echt systeemvenster openen.
    private var requestsByItself: Bool { !UserDefaults.standard.bool(forKey: "PullwatchSkipNotificationRequest") }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Meldingen")
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.notifications")
        .task {
            status = await model.notificationStatus()
            if status == .notDetermined && requestsByItself {
                asking = true
                await model.requestNotifications()
                asking = false
            }
            // Blijft kijken, zodat een wijziging in Systeeminstellingen hier meteen te zien is.
            while !Task.isCancelled {
                status = await model.notificationStatus()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var detail: LocalizedStringKey {
        switch status {
        case .authorized, .provisional, .ephemeral:
            "Pullwatch meldt een nieuwe PR of tag zodra die er is."
        case .denied:
            "Meldingen staan uit. Zet ze aan in Systeeminstellingen om nieuwe PR's en tags te zien zodra ze er zijn."
        default:
            asking ? "Wachten op je antwoord in de melding van macOS…" : "Pullwatch meldt een nieuwe PR of tag zodra die er is. macOS vraagt één keer om toestemming."
        }
    }

    @ViewBuilder private var trailing: some View {
        switch status {
        case .authorized, .provisional, .ephemeral:
            Label("Aan", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            Button("Open Systeeminstellingen") { Notifier.openSystemSettings() }
                .accessibilityIdentifier("onboarding.openNotificationSettings")
        default:
            if asking {
                ProgressView().controlSize(.small)
            } else {
                Button("Vragen") {
                    Task {
                        asking = true
                        await model.requestNotifications()
                        asking = false
                    }
                }
                .accessibilityIdentifier("onboarding.allowNotifications")
            }
        }
    }
}
