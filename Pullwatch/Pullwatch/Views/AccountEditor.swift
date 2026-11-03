import PullwatchCore
import SwiftUI

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
    /// Er staan tokens van de GitHub App bij dit account.
    @State private var signedInWithGitHub = false
    /// Waar de GitHub App is geïnstalleerd: de eigenaren om uit te kiezen; nil tot ze geladen zijn.
    @State private var installationOwners: [String]?
    /// Hoe het account inlogde toen de editor openging; een bestaand `gh`-account houdt die keuze.
    private let originalAuthMethod: AuthMethod

    init(model: AppModel, original: Account) {
        self.model = model
        _draft = State(initialValue: original)
        originalAuthMethod = original.authMethod
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
                // De naam volgt de organisatie (`Account.displayName`). Met de GitHub App komt ook
                // de eigenaar uit het inloggen: dan valt er niets te typen.
                if draft.authMethod != .gitHubApp {
                    TextField(draft.kind == .azureDevOps ? String(localized: "Organisatie") : String(localized: "Owner (user of org)"), text: $draft.organization)
                }
                Picker("Authenticatie", selection: $draft.authMethod) {
                    if offersGitHubApp {
                        Text("Inloggen met GitHub").tag(AuthMethod.gitHubApp)
                    }
                    Text("Personal Access Token").tag(AuthMethod.pat)
                    if offersCLI {
                        Text(draft.kind == .azureDevOps ? "Azure CLI (az login)" : "GitHub CLI (gh auth login)").tag(AuthMethod.cli)
                    }
                }
                if draft.authMethod == .gitHubApp {
                    GitHubSignInRow(model: model, accountId: draft.id) { _ in
                        signedInWithGitHub = true
                        Task { await loadInstallations() }
                    } onSignedOut: {
                        signedInWithGitHub = false
                        installationOwners = nil
                    }
                    if signedInWithGitHub {
                        ownerPicker
                    }
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
                        storedPAT ? String(localized: "Opgeslagen — leeg laten om te behouden") : String(localized: "Token"),
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

            VStack(alignment: .trailing, spacing: 4) {
                if let validationMessage {
                    Text(validationMessage).font(.caption).foregroundStyle(.secondary)
                }
                if let saveError {
                    Text(saveError).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Opslaan") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(validationMessage != nil)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            storedPAT = model.hasStoredPAT(draft.id)
            signedInWithGitHub = model.hasGitHubAppTokens(draft.id)
        }
        #if DEBUG
        .onChange(of: installationOwners) { _, _ in SnapshotCamera.shoot("account-editor", windowId: "main") }
        .onChange(of: availableRepos) { _, _ in SnapshotCamera.shoot("account-editor-repos", windowId: "main") }
        #endif
        .task(id: signedInWithGitHub && draft.authMethod == .gitHubApp) {
            guard signedInWithGitHub && draft.authMethod == .gitHubApp else { return }
            await loadInstallations()
            // Terug van de installatiepagina op github.com: de lijst opnieuw ophalen.
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                await loadInstallations()
            }
        }
        .onChange(of: draft.organization) { _, owner in
            guard draft.authMethod == .gitHubApp, !owner.isEmpty else { return }
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

    /// Kies waar de repositories staan: het eigen account of een organisatie met de app. Direct
    /// onder het inloggen, met daaronder de link om de app ergens anders te installeren.
    @ViewBuilder private var ownerPicker: some View {
        if let owners = installationOwners {
            if owners.isEmpty {
                Text("Pullwatch is nog nergens geïnstalleerd. Installeer het op je account of een organisatie; daarna verschijnt die hier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                installLink(first: true)
            } else {
                Picker("Repositories van", selection: $draft.organization) {
                    if !owners.contains(draft.organization) {
                        Text("Kies…").tag(draft.organization)
                    }
                    ForEach(owners, id: \.self) { owner in
                        Text(verbatim: owner).tag(owner)
                    }
                }
                .accessibilityIdentifier("github.owner")
                installLink(first: false)
            }
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Kijken waar Pullwatch is geïnstalleerd…").foregroundStyle(.secondary)
            }
        }
    }

    private func installLink(first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Link(first ? "Installeer Pullwatch op een account of organisatie" : "Installeer Pullwatch op een ander account of organisatie",
                 destination: model.gitHubApp.installURL)
                .font(.callout)
            Text("Bij een organisatie installeert een eigenaar Pullwatch, of keurt je verzoek goed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func loadInstallations() async {
        do {
            let owners = try await model.gitHubInstallationOwners(draft.id)
            installationOwners = owners
            // Eén plek: die meteen kiezen. De naam volgt de eigenaar, tenzij die al zelf gekozen was.
            if draft.organization.isEmpty, owners.count == 1 { draft.organization = owners[0] }
        } catch let error as ProviderError {
            repoError = error.userMessage
            installationOwners = []
        } catch {
            repoError = error.localizedDescription
            installationOwners = []
        }
    }

    private var hasRequiredFields: Bool {
        !draft.organization.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var validationMessage: LocalizedStringKey? {
        if draft.authMethod == .gitHubApp && !signedInWithGitHub { return "Log eerst in bij GitHub" }
        if draft.authMethod == .gitHubApp && !hasRequiredFields { return "Kies waar je repositories staan" }
        if !hasRequiredFields { return draft.kind == .azureDevOps ? "Vul de organisatie in" : "Vul de owner in" }
        if draft.authMethod == .pat && pat.isEmpty && !storedPAT { return "Vul een token in" }
        return nil
    }

    private func save() {
        if model.saveAccount(draft, pat: pat.isEmpty ? nil : pat) {
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
        ProviderFactory.make(draft, pat: pat.isEmpty ? nil : pat)
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
