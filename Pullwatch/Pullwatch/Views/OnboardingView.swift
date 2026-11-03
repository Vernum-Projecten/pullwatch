import AppKit
import PullwatchCore
import SwiftUI
import UserNotifications

/// Welkomstvenster bij de eerste start. Pullwatch heeft geen Dock-icoon en geen venster, dus
/// zonder dit lijkt de app na het openen niet te starten. Drie stappen: wat Pullwatch doet en
/// waar het icoon staat, het eerste account, en meldingen en starten bij inloggen.
struct OnboardingView: View {
    let model: AppModel

    enum Step: CaseIterable {
        case welcome, account, finish

        var previous: Step? {
            switch self {
            case .welcome: nil
            case .account: .welcome
            case .finish: .account
            }
        }
    }

    @State private var step = Step.welcome
    /// Het account dat nu wordt ingesteld; staat pas in de config na Toevoegen.
    @State private var draft: Account?
    /// De Toevoegen-knop van het concept, in de voetbalk.
    @State private var saveAction = AccountSaveAction()
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: WelcomeStep()
                case .account:
                    AccountStep(model: model, draft: $draft, saveAction: saveAction) {
                        draft = nil
                        step = .finish
                    }
                case .finish: FinishStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            OnboardingFooter(step: step, canContinue: !model.config.pollableAccounts.isEmpty, draftSave: draft == nil ? nil : saveAction) { action in
                switch action {
                case .back: back()
                case .start: step = .account
                case .skip, .next: step = .finish
                case .done: finish()
                }
            }
            .padding(16)
        }
        // Een vast formaat, zoals een installatie-assistent; het account-formulier scrolt zelf.
        .frame(width: 700, height: 660)
        #if DEBUG
        .onAppear { SnapshotCamera.shoot("onboarding-welcome", windowId: "onboarding") }
        .onChange(of: step) { _, step in SnapshotCamera.shoot("onboarding-\(step)", windowId: "onboarding") }
        .onChange(of: model.config.accounts.count) { _, _ in SnapshotCamera.shoot("onboarding-account-editor", windowId: "onboarding") }
        #endif
    }

    /// Terug: van een half ingesteld account naar de keuze GitHub of Azure DevOps (het concept
    /// vervalt), anders een stap terug.
    private func back() {
        switch step {
        case .welcome: break
        case .account:
            if let draft {
                model.discardDraft(draft.id)
                self.draft = nil
            } else {
                step = .welcome
            }
        case .finish: step = step.previous ?? .account
        }
    }

    private func finish() {
        if let draft { model.discardDraft(draft.id) }
        model.completeOnboarding()
        dismissWindow(id: "onboarding")
        if !model.config.pollableAccounts.isEmpty { model.show(.main) }
    }
}

/// De knoppen onder elke stap: Terug links, de volgende stap rechts (de standaardknop, Return).
private struct OnboardingFooter: View {
    enum Action { case back, start, skip, next, done }

    let step: OnboardingView.Step
    /// Er is al een account, dus "Volgende" in plaats van "Later instellen".
    let canContinue: Bool
    /// Een account wordt ingesteld: dan staat hier Toevoegen, grijs tot het account af is.
    let draftSave: AccountSaveAction?
    let perform: (Action) -> Void

    var body: some View {
        HStack {
            if step.previous != nil {
                Button("Terug") { perform(.back) }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("onboarding.back")
            }
            Spacer()
            switch step {
            case .welcome:
                Button("Aan de slag") { perform(.start) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.start")
            case .account where draftSave != nil:
                if let draftSave {
                    AddButton(action: draftSave)
                }
            case .account where canContinue:
                Button("Volgende") { perform(.next) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.next")
            case .account:
                Button("Later instellen") { perform(.skip) }
                    .accessibilityIdentifier("onboarding.skip")
            case .finish:
                Button("Klaar") { perform(.done) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.done")
            }
        }
        .controlSize(.large)
    }
}

/// Toevoegen in een voetbalk: grijs met de reden ernaast zolang het account niet af is, daarna
/// de blauwe standaardknop (ook met Return).
struct AddButton: View {
    let action: AccountSaveAction

    var body: some View {
        HStack(spacing: 10) {
            if let error = action.error {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if let reason = action.blockedReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
            Button("Toevoegen") { action.save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!action.canSave)
                .accessibilityIdentifier("account.save")
        }
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 18) {
            // Uit de eigen bundle: `applicationIconImage` geeft het icoon dat macOS voor deze
            // bundle id onthouden heeft, bijvoorbeeld van een oudere versie in Programma's.
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
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
/// Tekststijlen in plaats van vaste maten, zodat hij meegroeit met grotere tekst; voor VoiceOver
/// één beschrijving in plaats van losse symbolen.
struct MenuBarHint: View {
    var body: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            Image(systemName: AppModel.menuBarSymbolName)
                .fontWeight(.semibold)
                .padding(6)
                .background(Circle().fill(.tint.opacity(0.18)))
                .overlay(Circle().strokeBorder(.tint, lineWidth: 2))
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Image(systemName: "switch.2")
            Text(Date.now, format: .dateTime.weekday(.abbreviated).hour().minute())
                .monospacedDigit()
        }
        .font(.body)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: 440)
        .background(.bar, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("De menubalk, met het Pullwatch-icoon rechtsboven naast de klok"))
    }
}

private struct AccountStep: View {
    let model: AppModel
    @Binding var draft: Account?
    let saveAction: AccountSaveAction
    let onAdded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Je eerste account")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 20)
            if let account = draft {
                Text(account.authMethod == .gitHubApp
                     ? "Log in met GitHub, kies waar je repositories staan en welke je volgt, en klik op Toevoegen."
                     : "Vul de gegevens in en klik op Toevoegen. Met de Azure CLI (az login) heb je geen token nodig.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                AccountEditor(model: model, original: account, saveAction: saveAction, onSaved: onAdded).id(account.id)
            } else {
                let added = model.config.pollableAccounts
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
                    .padding(.horizontal, 20)
                HStack(spacing: 16) {
                    ProviderChoice(title: "GitHub", detail: "Een gebruiker of organisatie op github.com", symbol: "chevron.left.forwardslash.chevron.right") {
                        start(.gitHub)
                    }
                    .accessibilityIdentifier("onboarding.addGitHub")
                    ProviderChoice(title: "Azure DevOps", detail: "Een organisatie op dev.azure.com", symbol: "cloud") {
                        start(.azureDevOps)
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

    private func start(_ kind: ProviderKind) {
        draft = Account(kind: kind, organization: "", authMethod: model.defaultAuthMethod(for: kind))
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
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 540)
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
        LabeledContent {
            trailing
        } label: {
            Text("Meldingen")
            Text(detail)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.notifications")
        .task {
            status = await model.notificationStatus()
            if status == .notDetermined && requestsByItself { await ask() }
            // Terug uit Systeeminstellingen: de nieuwe stand meteen laten zien.
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                status = await model.notificationStatus()
            }
        }
    }

    private func ask() async {
        asking = true
        await model.requestNotifications()
        status = await model.notificationStatus()
        asking = false
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
                Button("Vragen") { Task { await ask() } }
                .accessibilityIdentifier("onboarding.allowNotifications")
            }
        }
    }
}
