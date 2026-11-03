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
    @State private var availableRepos: [String] = []
    @State private var repoSearch = ""
    @State private var repoError: String?
    @State private var loadingRepos = false
    @State private var storedPAT = false
    @State private var saveError: String?
    @State private var testTask: Task<Void, Never>?
    @State private var reposTask: Task<Void, Never>?
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
            Section("Account") {
                Picker("Authenticatie", selection: $draft.authMethod) {
                    if offersGitHubApp {
                        Text("Inloggen met GitHub").tag(AuthMethod.gitHubApp)
                    }
                    Text("Personal Access Token").tag(AuthMethod.pat)
                    if offersCLI {
                        Text(draft.kind == .azureDevOps ? "Azure CLI (az login)" : "GitHub CLI (gh auth login)").tag(AuthMethod.cli)
                    }
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

            Section("Meldingen") {
                Toggle("Draft-PR's meenemen", isOn: $draft.includeDrafts)
                Toggle("Eigen PR's verbergen", isOn: $draft.hideOwn)
            }

            Section("Repositories") {
                Picker("Nieuwe repo's volgen", selection: $draft.newRepoDefault) {
                    Text("Niets").tag(NewRepoDefault.none)
                    Text("PR's").tag(NewRepoDefault.prs)
                }

                HStack {
                    TextField("Zoeken", text: $repoSearch)
                    Button(loadingRepos ? "Laden…" : "Repos laden") {
                        reposTask?.cancel()
                        reposTask = Task { await loadRepos() }
                    }
                    .disabled(!hasRequiredFields || reposTask != nil)
                }
                if let repoError {
                    Text(repoError).font(.caption).foregroundStyle(.red)
                }
                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            Text("Repo").font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Toggle("Alle PR's", sources: filteredRepos.map { binding(for: $0, \.prs) }, isOn: \.self)
                                    .tint(ItemKind.pullRequest.color)
                                    .help("PR's aan/uit voor alle zichtbare repo's")
                                    .disabled(filteredRepos.isEmpty)
                                Text("PR's").font(.caption).foregroundStyle(ItemKind.pullRequest.color)
                                AllNotifyButton(sources: filteredRepos.map { binding(for: $0, \.notifyPRs) })
                            }
                            HStack(spacing: 4) {
                                Toggle("Alle tags", sources: filteredRepos.map { binding(for: $0, \.tags) }, isOn: \.self)
                                    .tint(ItemKind.tag.color)
                                    .help("Tags aan/uit voor alle zichtbare repo's")
                                    .disabled(filteredRepos.isEmpty)
                                Text("Tags").font(.caption).foregroundStyle(ItemKind.tag.color)
                                AllNotifyButton(sources: filteredRepos.map { binding(for: $0, \.notifyTags) })
                            }
                            HStack(spacing: 4) {
                                Toggle("Alle completed", sources: filteredRepos.map { binding(for: $0, \.completed) }, isOn: \.self)
                                    .tint(PRState.merged.color)
                                    .help("Completed aan/uit voor alle zichtbare repo's")
                                    .disabled(filteredRepos.isEmpty)
                                Text("Completed").font(.caption).foregroundStyle(PRState.merged.color)
                                AllNotifyButton(sources: filteredRepos.map { binding(for: $0, \.notifyCompleted) })
                            }
                            .help("Melding als een PR in deze repo gemerged wordt (binnen ~15 minuten)")
                        }
                        Divider()
                        ForEach(filteredRepos, id: \.self) { repo in
                            GridRow {
                                Text(repo)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                watchCell(repo, \.prs, notify: \.notifyPRs, tint: ItemKind.pullRequest.color)
                                watchCell(repo, \.tags, notify: \.notifyTags, tint: ItemKind.tag.color)
                                watchCell(repo, \.completed, notify: \.notifyCompleted, tint: PRState.merged.color)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 140)
            }

            if saveAction == nil {
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
        .onChange(of: draft.owners) { _, owners in
            guard draft.authMethod == .gitHubApp, !owners.isEmpty else { return }
            reposTask?.cancel()
            reposTask = Task { await loadRepos() }
        }
        .onDisappear {
            testTask?.cancel()
            reposTask?.cancel()
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

    private var filteredRepos: [String] {
        let sorted = Account.mergedRepoNames(available: availableRepos, configured: Array(draft.repoWatch.keys))
        guard !repoSearch.isEmpty else { return sorted }
        return sorted.filter { $0.localizedCaseInsensitiveContains(repoSearch) }
    }

    /// Vinkje voor volgen plus belletje voor de melding; het belletje doet pas iets als je volgt.
    private func watchCell(
        _ repo: String,
        _ field: WritableKeyPath<WatchSet, Bool>,
        notify: WritableKeyPath<WatchSet, Bool>,
        tint: Color
    ) -> some View {
        HStack(spacing: 4) {
            Toggle("Volgen", isOn: binding(for: repo, field))
                .tint(tint)
            NotifyButton(isOn: binding(for: repo, notify))
                .disabled(!draft.watch(for: repo)[keyPath: field])
        }
    }

    private func binding(for repo: String, _ field: WritableKeyPath<WatchSet, Bool>) -> Binding<Bool> {
        Binding(
            get: { draft.watch(for: repo)[keyPath: field] },
            set: { isOn in
                var watch = draft.watch(for: repo)
                watch[keyPath: field] = isOn
                draft.setWatch(watch, for: repo)
            }
        )
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
            connectionMessage = "✓ " + String(localized: "Verbonden als \(name)", comment: "Naam van de ingelogde gebruiker")
        } catch let error as ProviderError {
            if Task.isCancelled { return }
            connectionMessage = "✗ \(error.userMessage)"
        } catch {
            if Task.isCancelled { return }
            connectionMessage = "✗ \(error.localizedDescription)"
        }
    }

    private func loadRepos() async {
        loadingRepos = true
        repoError = nil
        defer {
            loadingRepos = false
            reposTask = nil
        }
        do {
            let repos = try await provider().listRepos()
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

/// Belletje: wel of geen melding voor iets dat je volgt.
private struct NotifyButton: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: isOn ? "bell.fill" : "bell.slash")
                .foregroundStyle(isOn && isEnabled ? Color.primary : Color.secondary)
                .opacity(isEnabled ? 1 : 0.3)
        }
        .buttonStyle(.borderless)
        .help(isOn ? String(localized: "Melding aan; klik om alleen te volgen zonder melding") : String(localized: "Geen melding; staat wel in menu en geschiedenis"))
    }
}

/// Belletje in de kop: alles aan, of alles uit als alles al aan staat.
private struct AllNotifyButton: View {
    let sources: [Binding<Bool>]

    private var allOn: Bool { sources.allSatisfy(\.wrappedValue) }

    var body: some View {
        Button {
            let target = !allOn
            for source in sources { source.wrappedValue = target }
        } label: {
            Image(systemName: allOn ? "bell.fill" : "bell.slash")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .disabled(sources.isEmpty)
        .help(allOn ? String(localized: "Meldingen uit voor alle zichtbare repo's") : String(localized: "Meldingen aan voor alle zichtbare repo's"))
    }
}
