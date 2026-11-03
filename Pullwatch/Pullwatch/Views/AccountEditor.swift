import PullwatchCore
import PullwatchGitHub
import SwiftUI

/// Laat een venster de Toevoegen-knop van een account-editor in zijn eigen voetbalk zetten (het
/// welkomstvenster, het toevoeg-venster), in plaats van onderaan in het scrollende formulier.
/// De editor houdt bij of het account af is en waarom niet; de voetbalk roept `save()` aan.
@MainActor
@Observable
final class AccountSaveAction {
    /// Waarom het nog niet kan ("Log eerst in bij GitHub"); nil als Toevoegen kan.
    fileprivate(set) var blockedReason: LocalizedStringKey?
    fileprivate(set) var error: String?
    @ObservationIgnored fileprivate var perform: () -> Void = {}

    var canSave: Bool { blockedReason == nil }

    func save() { perform() }
}

struct AccountEditor: View {
    let model: AppModel

    @State private var draft: Account
    @State private var pat = ""
    @State private var connectionMessage: String?
    /// De repositories van de dienst; de vorige lijst blijft staan zolang een nieuwe laadt.
    @State private var availableRepos: [String] = []
    @State private var isLoadingRepos = false
    @State private var repoError: String?
    /// Opnieuw laden met de knop.
    @State private var reloadCount = 0
    @State private var storedPAT = false
    @State private var saveError: String?
    @State private var testTask: Task<Void, Never>?
    /// Accounts waarmee `gh` is ingelogd; leeg tot ze geladen zijn.
    @State private var ghAccounts: [String] = []
    /// Inloggen met GitHub voor dit account (code, goedkeuring, installaties); nil bij een
    /// andere manier van inloggen.
    @State private var signIn: GitHubSignIn?
    /// Hoe het account inlogde toen de editor openging; een bestaand `gh`-account houdt die keuze.
    private let originalAuthMethod: AuthMethod

    /// Een nieuw account (nog niet in de config): de knop heet Toevoegen, en pas dan wordt
    /// er iets bewaard.
    private let isNew: Bool
    /// Na een geslaagd bewaren, bijvoorbeeld om het venster te sluiten.
    private let onSaved: () -> Void

    /// Zet de Toevoegen-knop buiten de editor (in een voetbalk); nil: de editor toont hem zelf.
    private let saveAction: AccountSaveAction?

    init(model: AppModel, original: Account, saveAction: AccountSaveAction? = nil, onSaved: @escaping () -> Void = {}) {
        self.model = model
        self.saveAction = saveAction
        _draft = State(initialValue: original)
        originalAuthMethod = original.authMethod
        isNew = !model.config.accounts.contains { $0.id == original.id }
        self.onSaved = onSaved
    }

    /// Inloggen met GitHub kan zodra de GitHub App is ingesteld.
    private var offersGitHubApp: Bool {
        draft.kind == .gitHub && (model.gitHubApp.isConfigured || originalAuthMethod == .gitHubApp)
    }

    /// `gh` alleen nog voor accounts die het al gebruiken, of zolang er geen GitHub App is.
    private var offersCLI: Bool {
        draft.kind == .azureDevOps || originalAuthMethod == .cli || !model.gitHubApp.isConfigured
    }

    var body: some View {
        Form {
            Section("Inloggen") {
                if isNew {
                    Picker("Authenticatie", selection: $draft.authMethod) {
                        if offersGitHubApp {
                            Text("Inloggen met GitHub").tag(AuthMethod.gitHubApp)
                        }
                        Text("Personal Access Token").tag(AuthMethod.pat)
                        if offersCLI {
                            Text(draft.kind == .azureDevOps ? "Azure CLI (az login)" : "GitHub CLI (gh auth login)").tag(AuthMethod.cli)
                        }
                    }
                } else {
                    // Een bestaand account houdt zijn manier van inloggen; anders opnieuw toevoegen.
                    LabeledContent("Authenticatie") { Text(methodName) }
                }
                if draft.authMethod == .gitHubApp, let signIn {
                    GitHubSignInRow(signIn: signIn)
                }
                // Eerst hoe je inlogt, dan waar de repositories staan, dan het token. De naam volgt de
                // organisatie (`Account.displayName`); met de GitHub App komt de eigenaar uit het
                // inloggen, dan valt er niets te typen.
                if draft.authMethod != .gitHubApp {
                    TextField(draft.kind == .azureDevOps ? String(localized: "Organisatie") : String(localized: "Owner (user of org)"), text: $draft.organization)
                }
                if draft.kind == .gitHub && draft.authMethod == .cli {
                    Picker("GitHub-account", selection: $draft.cliUser) {
                        Text("Actief account in gh").tag(String?.none)
                        ForEach(ghAccountChoices, id: \.self) { login in
                            Text(verbatim: login).tag(String?.some(login))
                        }
                    }
                    .help("Welk account uit `gh auth status` het token levert; handig als je met meerdere GitHub-accounts bent ingelogd")
                    .task { ghAccounts = await GhCLIAccounts.list(runner: SystemProcessRunner()) }
                }
                if draft.authMethod == .pat {
                    SecureField(
                        storedPAT ? String(localized: "Opgeslagen, laat leeg om te behouden") : String(localized: "Token"),
                        text: $pat
                    )
                    if !isNew && !pat.isEmpty {
                        HStack {
                            Spacer()
                            Button("Token bewaren") { save() }
                        }
                    }
                }
                if draft.authMethod != .gitHubApp {
                HStack {
                    Button("Test verbinding") {
                        testTask?.cancel()
                        testTask = Task { await testConnection() }
                    }
                    .disabled(!hasRequiredFields || testTask != nil)
                    if let connectionMessage {
                        Text(connectionMessage).font(.caption)
                    }
                }
                }
            }

            if draft.authMethod == .gitHubApp, let signIn, signIn.isSignedIn {
                Section("Repositories van") {
                    GitHubInstallationsRow(signIn: signIn, owners: $draft.owners)
                }
            }

            Section {
                Toggle("Draft-PR's meenemen", isOn: $draft.includeDrafts)
                Toggle("Eigen PR's verbergen", isOn: $draft.hideOwn)
            } header: {
                Text("Welke PR's tellen mee")
            } footer: {
                Text("Geldt overal: in het menu, de geschiedenis en de meldingen.")
            }

            if draft.isComplete {
                RepoFollowList(account: $draft, available: availableRepos, isLoading: isLoadingRepos, error: repoError) { reloadCount += 1 }
            }

            if isNew && saveAction == nil {
            VStack(alignment: .trailing, spacing: 4) {
                if let validationMessage {
                    Text(validationMessage).font(.caption).foregroundStyle(.secondary)
                }
                if let saveError {
                    Text(saveError).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button(isNew ? "Toevoegen" : "Opslaan") { save() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("account.save")
                        .disabled(validationMessage != nil)
                }
            }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            storedPAT = model.hasStoredPAT(draft.id)
            saveAction?.perform = { save() }
            saveAction?.blockedReason = validationMessage
        }
        .onChange(of: validationMessage) { _, message in saveAction?.blockedReason = message }
        .onChange(of: saveError) { _, error in saveAction?.error = error }
        .task(id: draft.authMethod) {
            guard draft.authMethod == .gitHubApp else {
                signIn = nil
                return
            }
            let signIn = self.signIn ?? GitHubSignIn(model: model, accountId: draft.id)
            self.signIn = signIn
            // Terug in de app (bijvoorbeeld van de installatiepagina op github.com): opnieuw kijken.
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                await signIn.refreshInstallations()
            }
        }
        #if DEBUG
        .onChange(of: signIn?.phase) { _, phase in
            let name = switch phase {
            case .signedOut, nil: "signed-out"
            case .requestingCode: "requesting-code"
            case .waitingForApproval: "waiting-for-approval"
            case .signedIn: "signed-in"
            }
            SnapshotCamera.shoot("github-\(name)")
        }
        .onChange(of: signIn?.waitingForInstall) { _, waiting in
            if waiting == true { SnapshotCamera.shoot("github-waiting-for-install") }
        }
        .onChange(of: availableRepos) { _, _ in SnapshotCamera.shoot("github-repositories") }
        #endif
        .onChange(of: signIn?.installations) { old, installations in
            guard case .found(let found) = installations else { return }
            let logins = found.map(\.login)
            switch old {
            case .found(let before)?:
                // Terwijl dit venster open is ergens anders geïnstalleerd: die nieuwe plek volgen.
                let known = before.map(\.login)
                draft.owners += logins.filter { !known.contains($0) && !draft.owners.contains($0) }
            case .none?:
                // Daarnet nog nergens geïnstalleerd, nu wel: wat er nu staat volgen.
                draft.owners += logins.filter { !draft.owners.contains($0) }
            case .unknown?, nil:
                // De lijst voor het eerst: een nieuw account volgt alles, een bestaand blijft zoals het was.
                if isNew && draft.owners.isEmpty { draft.owners = logins }
            }
        }
        .onChange(of: signIn?.login) { _, login in
            if let login { draft.login = login }
        }
        // Bestaand account: elke wijziging meteen bewaren (geen Opslaan in Instellingen).
        .onChange(of: draft) { _, account in
            if !isNew { model.updateAccount(account) }
        }
        // De repositories laden vanzelf, opnieuw als de plekken of het inloggen veranderen.
        .task(id: RepoLoad(owners: draft.owners, method: draft.authMethod, cliUser: draft.cliUser, hasNewToken: !pat.isEmpty, signedIn: signIn?.isSignedIn ?? false, reload: reloadCount)) {
            await loadRepos()
        }
        .onDisappear {
            testTask?.cancel()
        }
    }

    /// Ook een eerder gekozen account dat `gh` nu niet (meer) kent, zodat de keuze zichtbaar blijft.
    private var ghAccountChoices: [String] {
        guard let chosen = draft.cliUser, !ghAccounts.contains(chosen) else { return ghAccounts }
        return ghAccounts + [chosen]
    }

    private var hasRequiredFields: Bool { draft.isComplete }

    private var validationMessage: LocalizedStringKey? {
        if draft.authMethod == .gitHubApp && signIn?.isSignedIn != true { return "Log eerst in bij GitHub" }
        if draft.authMethod == .gitHubApp && !hasRequiredFields { return "Volg minstens één plek" }
        if !hasRequiredFields { return draft.kind == .azureDevOps ? "Vul de organisatie in" : "Vul de owner in" }
        if draft.authMethod == .pat && pat.isEmpty && !storedPAT { return "Vul een token in" }
        return nil
    }

    private func save() {
        if model.saveAccount(draft, pat: pat.isEmpty ? nil : pat) {
            onSaved()
            saveError = nil
            pat = ""
            storedPAT = draft.authMethod == .pat ? (storedPAT || model.hasStoredPAT(draft.id)) : false
        } else {
            saveError = String(localized: "PAT opslaan in Keychain mislukt")
        }
    }

    private func provider() -> any PRProvider {
        model.provider(for: draft, pat: pat.isEmpty ? nil : pat)
    }

    private func testConnection() async {
        connectionMessage = String(localized: "Bezig…")
        defer { testTask = nil }
        do {
            let name = try await provider().testConnection()
            if Task.isCancelled { return }
            connectionMessage = String(localized: "✓ Verbonden als \(name)", comment: "Naam van de ingelogde gebruiker")
        } catch let error as ProviderError {
            if Task.isCancelled { return }
            connectionMessage = "✗ \(error.userMessage)"
        } catch {
            if Task.isCancelled { return }
            connectionMessage = "✗ \(error.localizedDescription)"
        }
    }

    /// Wanneer de repositories opnieuw moeten laden.
    private struct RepoLoad: Equatable {
        let owners: [String]
        let method: AuthMethod
        let cliUser: String?
        let hasNewToken: Bool
        let signedIn: Bool
        let reload: Int
    }

    private var methodName: LocalizedStringKey {
        switch draft.authMethod {
        case .gitHubApp: "Inloggen met GitHub"
        case .pat: "Personal Access Token"
        case .cli: draft.kind == .azureDevOps ? "Azure CLI (az login)" : "GitHub CLI (gh auth login)"
        }
    }

    private func loadRepos() async {
        guard draft.isComplete, draft.authMethod != .gitHubApp || signIn?.isSignedIn == true,
              draft.authMethod != .pat || storedPAT || !pat.isEmpty else {
            isLoadingRepos = false
            return
        }
        isLoadingRepos = true
        repoError = nil
        defer { if !Task.isCancelled { isLoadingRepos = false } }
        do {
            let repos = try await model.repositories(for: draft, pat: pat.isEmpty ? nil : pat)
            if Task.isCancelled { return }
            availableRepos = repos
        } catch let error as ProviderError {
            if Task.isCancelled { return }
            repoError = error.userMessage
        } catch {
            if Task.isCancelled { return }
            repoError = error.localizedDescription
        }
    }
}
