import AppKit
import PullwatchCore
import SwiftUI
import UserNotifications

/// Welkomstvenster bij de eerste start. Pullwatch heeft geen Dock-icoon en geen venster, dus
/// zonder dit lijkt de app na het openen niet te starten. Drie stappen: wat Pullwatch doet en
/// waar het icoon staat, het eerste account, en meldingen en starten bij inloggen.
struct OnboardingView: View {
    @Environment(AccountsModel.self) private var accounts
    @Environment(AppRouter.self) private var router

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
    /// Het concept is een GitHub-account op GitHub Enterprise.
    @State private var draftIsEnterprise = false
    /// De Toevoegen-knop van het concept, in de voetbalk.
    @State private var saveAction = AccountSaveAction()
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: WelcomeStep()
                case .account:
                    AccountStep(draft: $draft, enterprise: $draftIsEnterprise, saveAction: saveAction) {
                        draft = nil
                        step = .finish
                    }
                case .finish: FinishStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            OnboardingFooter(step: step, canContinue: !accounts.config.pollableAccounts.isEmpty, draftSave: draft == nil ? nil : saveAction) { action in
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
        .onChange(of: accounts.config.accounts.count) { _, _ in SnapshotCamera.shoot("onboarding-account-editor", windowId: "onboarding") }
        .task { await tour() }
        #endif
    }

    /// Terug: van een half ingesteld account naar de keuze van de dienst (het concept
    /// vervalt), anders een stap terug.
    private func back() {
        switch step {
        case .welcome: break
        case .account:
            if let draft {
                accounts.discardDraft(draft.id)
                self.draft = nil
            } else {
                step = .welcome
            }
        case .finish: step = step.previous ?? .account
        }
    }

    #if DEBUG
    /// Alleen in debug-builds, met `-PullwatchOnboardingTour YES` (en `-PullwatchSnapshotDirectory`):
    /// loopt zelf langs elke stap, ook de keuze van de dienst en elk formulier, zodat
    /// de camera ze vastlegt zonder muis of toetsenbord. Inloggen met GitHub start hij niet: dat
    /// zet de code op het klembord.
    private func tour() async {
        guard UserDefaults.standard.bool(forKey: "PullwatchOnboardingTour") else { return }
        if UserDefaults.standard.bool(forKey: "PullwatchSnapshotDark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else if UserDefaults.standard.bool(forKey: "PullwatchSnapshotLight") {
            // Licht ook als de Mac donker staat, zodat beide varianten (zoals het GitHub-logo) te zien zijn.
            NSApp.appearance = NSAppearance(named: .aqua)
        }
        let pause = Duration.seconds(1.5)
        try? await Task.sleep(for: pause)
        step = .account
        try? await Task.sleep(for: pause)
        for choice in AccountChoice.all {
            draftIsEnterprise = choice.enterprise
            draft = accounts.draft(for: choice)
            try? await Task.sleep(for: pause)
            SnapshotCamera.shoot("onboarding-draft-\(choice.id)", windowId: "onboarding")
            try? await Task.sleep(for: pause)
            back()
            try? await Task.sleep(for: .milliseconds(300))
        }
        step = .finish
    }
    #endif

    private func finish() {
        if let draft { accounts.discardDraft(draft.id) }
        accounts.completeOnboarding()
        dismissWindow(id: "onboarding")
        if !accounts.config.pollableAccounts.isEmpty { router.show(.main) }
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
                ForwardButton("Aan de slag") { perform(.start) }
                    .accessibilityIdentifier("onboarding.start")
            case .account where draftSave != nil:
                if let draftSave {
                    AddButton(action: draftSave)
                }
            case .account where canContinue:
                ForwardButton("Volgende") { perform(.next) }
                    .accessibilityIdentifier("onboarding.next")
            case .account:
                // Grijs, geen standaardknop: zonder account is de stap niet af.
                Button("Later instellen") { perform(.skip) }
                    .help("Zonder account verder; je voegt er later een toe onder Instellingen")
                    .accessibilityIdentifier("onboarding.skip")
            case .finish:
                ForwardButton("Klaar") { perform(.done) }
                    .accessibilityIdentifier("onboarding.done")
            }
        }
        .controlSize(.large)
    }
}

/// De knop naar de volgende stap: de blauwe standaardknop, ook met Return.
private struct ForwardButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
    }
}

/// Een stap die in het vaste venster past staat gecentreerd; past hij niet (grotere tekst, een
/// langere vertaling), dan scrolt hij in plaats van af te kappen.
struct FitsOrScrolls<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView {
                content.frame(maxWidth: .infinity)
            }
        }
    }
}
