import Foundation
import Observation
import PullwatchCore
import PullwatchGitHub

nonisolated private let logger = Log(category: "app")

/// Waarom een ingetypte of geplakte repository niet toegevoegd kan worden, in gewone woorden.
struct RepositoryInputError: Error, Equatable {
    let message: String
}

/// De instellingen (`AppConfig` in config.json) en de accounts met hun inloggegevens in de
/// Keychain: bewaren, wijzigen, weggooien, inloggen met GitHub en de losse repo's. Wat een
/// wijziging elders in gang zet (opnieuw pollen, de geschiedenis) regelt `AppModel`.
@Observable
final class AccountsModel {
    private(set) var config: AppConfig {
        didSet { didChangeConfig() }
    }

    /// Wat Pullwatch deze sessie over de losse repo's weet, per `extraRepoKey`: zonder inloggen
    /// gelezen, of niet (meer) gevonden. Ontbreekt: met het token, of nog niet bekeken.
    private(set) var extraRepoStatus: [String: ExtraRepoStatus] = [:]

    enum ExtraRepoStatus: Equatable {
        case readWithoutSignIn
        case problem(String)
    }

    /// Na elke wijziging van `config`; `AppModel` werkt er het overzicht mee bij.
    @ObservationIgnored var didChangeConfig: () -> Void = {}
    /// Of config.json te lezen was; zo niet, dan ruimt `removeOrphanTokens()` niets op.
    @ObservationIgnored private var configReadable = true
    @ObservationIgnored private var extraRepoChecked: Set<String> = []
    @ObservationIgnored private let services: AppServices

    init(services: AppServices) {
        self.services = services
        do {
            config = try services.configStore.load() ?? AppConfig()
        } catch {
            logger.error("config onleesbaar: \(error.localizedDescription)")
            config = AppConfig()
            configReadable = false
        }
    }

    /// De Pullwatch GitHub App uit de xcconfig; niet ingesteld = geen "Inloggen met GitHub".
    var gitHubApp: GitHubAppConfig { services.gitHubApp }

    // MARK: - Welkom

    /// Het welkomstvenster is afgerond (of overgeslagen); daarna komt het niet vanzelf terug.
    var onboardingCompleted: Bool { config.onboardingCompleted }
    /// Eerste start: nog geen bruikbaar account en het welkomstvenster nooit afgerond.
    var needsOnboarding: Bool { !onboardingCompleted && config.pollableAccounts.isEmpty }

    func completeOnboarding() {
        guard !config.onboardingCompleted else { return }
        config.onboardingCompleted = true
        save()
    }

    // MARK: - Instellingen

    /// Wijzigt de instellingen en bewaart ze meteen (Instellingen hebben geen Opslaan).
    func edit(_ change: (inout AppConfig) -> Void) {
        change(&config)
        save()
    }

    /// Een bron aan of uit (Instellingen, Bronnen), als binding voor de schakelaar. Er start geen
    /// check: de volgende check vraagt de bron niet meer (of weer); wat eerder van de bron kwam,
    /// staat meteen niet meer als actueel (`VersionsModel.configChanged()`).
    subscript(sourceEnabled id: DataSourceID) -> Bool {
        get { config.isEnabled(id) }
        set {
            guard config.isEnabled(id) != newValue else { return }
            edit { config in
                if newValue { config.disabledSources.remove(id) } else { config.disabledSources.insert(id) }
            }
        }
    }

    private func save() {
        do {
            try services.configStore.save(config)
        } catch {
            logger.error("config opslaan mislukt: \(error.localizedDescription)")
        }
    }

    // MARK: - Accounts

    /// Bewaart een account. Een nieuw account moet af zijn (minstens één eigenaar); een bestaand
    /// mag niets volgen (gepauzeerd). False (en er verandert niets) als dat niet klopt of de PAT
    /// niet in de Keychain kon.
    func saveAccount(_ account: Account, pat: String?) -> Bool {
        let exists = config.accounts.contains { $0.id == account.id }
        guard account.isComplete || exists else { return false }
        let secrets = services.secrets
        // Alleen de inloggegevens van de gekozen manier blijven bewaard.
        if account.authMethod != .gitHubApp {
            GitHubAppTokenStore(accountId: account.id, secrets: secrets).delete()
        }
        if account.authMethod != .pat {
            try? secrets.delete(account: account.id.uuidString)
        } else if let pat, !pat.isEmpty {
            do {
                try secrets.write(pat, account: account.id.uuidString)
            } catch {
                logger.error("PAT opslaan mislukt: \(error.localizedDescription)")
                return false
            }
        }
        if let index = config.accounts.firstIndex(where: { $0.id == account.id }) {
            config.accounts[index] = account
        } else {
            config.accounts.append(account)
        }
        save()
        return true
    }

    /// Een wijziging aan een bestaand account, meteen bewaard. False als er niets veranderde.
    func updateAccount(_ account: Account) -> Bool {
        guard let index = config.accounts.firstIndex(where: { $0.id == account.id }), config.accounts[index] != account else { return false }
        config.accounts[index] = account
        save()
        return true
    }

    /// Haalt het account en zijn inloggegevens weg; de geschiedenis ervan ruimt `AppModel` op.
    func removeAccount(_ id: UUID) {
        try? services.secrets.delete(account: id.uuidString)
        GitHubAppTokenStore(accountId: id, secrets: services.secrets).delete()
        config.accounts.removeAll { $0.id == id }
        save()
    }

    /// Een account dat in een venster werd ingesteld maar niet bewaard: de inloggegevens die
    /// er al voor in de Keychain kwamen gaan weg, er komt niets in de config.
    func discardDraft(_ id: UUID) {
        guard !config.accounts.contains(where: { $0.id == id }) else { return }
        try? services.secrets.delete(account: id.uuidString)
        GitHubAppTokenStore(accountId: id, secrets: services.secrets).delete()
    }

    /// Volgen en meldingen van één repo; false als het account er niet (meer) is.
    func setWatch(_ set: WatchSet, repo: String, accountId: UUID) -> Bool {
        guard let index = config.accounts.firstIndex(where: { $0.id == accountId }) else { return false }
        config.accounts[index].setWatch(set, for: repo)
        save()
        return true
    }

    func watch(repo: String, accountId: UUID) -> WatchSet {
        config.accounts.first { $0.id == accountId }?.watch(for: repo) ?? .none
    }

    /// Lege accounts (zonder organisatie) die een oudere versie bij "+" meteen bewaarde. Een
    /// gepauzeerd account (ingelogd, niets gevolgd) blijft staan; alleen echt lege.
    var incompleteAccounts: [Account] {
        config.accounts.filter { !$0.isComplete && $0.login == nil && $0.repoWatch.isEmpty }
    }

    /// Tokens van accounts die er niet meer zijn (afgebroken toevoegen, crash, oudere versie).
    /// Nooit bij een onleesbare config: dan zou elk token als los gelden.
    func removeOrphanTokens() {
        guard configReadable else { return }
        let orphans = SecretStores.removeOrphans(keeping: Set(config.accounts.map(\.id)))
        if orphans > 0 { logger.notice("\(orphans) losse tokens uit de Keychain verwijderd") }
    }

    #if DEBUG
    /// Met het nagespeelde GitHub: accounts uit een test-config krijgen een nep-token, zodat ze
    /// zonder inloggen "ingelogd" zijn (schermafbeeldingen, UI-tests).
    func installFakeTokens() {
        guard FakeGitHub.isEnabled else { return }
        for account in config.accounts where account.authMethod == .gitHubApp && !hasGitHubAppTokens(account.id) {
            try? GitHubAppTokenStore(accountId: account.id, secrets: services.secrets)
                .save(GitHubAppTokens(access: "fake-access", accessExpires: .distantFuture, refresh: "fake-refresh"))
        }
    }
    #endif

    // MARK: - Losse repo's

    /// Accounts waar je een losse repo aan kunt toevoegen.
    var accountsForExtraRepos: [Account] {
        config.accounts.filter { $0.isComplete && $0.kind.supportsExtraRepos }
    }

    func extraRepoKey(accountId: UUID, repo: String) -> String {
        Account.repoKey(accountId: accountId, repo: repo)
    }

    /// De repositories die bij een account te volgen zijn (van alle eigenaren).
    func repositories(for account: Account, pat: String? = nil) async throws -> [String] {
        try await provider(for: account, pat: pat).listRepos()
    }

    /// Leest wat iemand intypte of plakte en controleert de repo met één verzoek. Geeft de
    /// repo zoals de dienst hem schrijft, of een foutmelding in gewone woorden.
    func checkRepository(_ input: String, for account: Account, pat: String? = nil) async -> Result<RepositoryCheck, RepositoryInputError> {
        let repo: String
        do {
            repo = try RepositoryReference.parse(
                input, kind: account.kind, organization: account.organization,
                instanceURL: account.kind == .gitLab
                    ? account.effectiveInstanceURL
                    : (account.isGitHubEnterprise ? account.instanceURL : nil)
            )
        } catch {
            return .failure(RepositoryInputError(message: error.userMessage))
        }
        if account.isExtra(repo) {
            return .failure(RepositoryInputError(message: RepositoryProblem.alreadyAdded(repo).userMessage))
        }
        do {
            let check = try await provider(for: account, pat: pat).checkRepository(repo)
            if account.isExtra(check.name) {
                return .failure(RepositoryInputError(message: RepositoryProblem.alreadyAdded(check.name).userMessage))
            }
            remember(check, accountId: account.id)
            return .success(check)
        } catch let problem as RepositoryProblem {
            return .failure(RepositoryInputError(message: problem.userMessage))
        } catch let error as ProviderError {
            return .failure(RepositoryInputError(message: error.userMessage))
        } catch {
            return .failure(RepositoryInputError(message: error.localizedDescription))
        }
    }

    /// Kijkt eens per sessie hoe de losse repo's van een account te lezen zijn, voor de regel
    /// "Gelezen zonder inloggen" of een melding als er een niet meer gevonden wordt.
    func refreshExtraRepoStatus(_ account: Account, pat: String? = nil) async {
        let unknown = account.extraRepos.filter { extraRepoChecked.insert(extraRepoKey(accountId: account.id, repo: $0)).inserted }
        guard !unknown.isEmpty else { return }
        let provider = provider(for: account, pat: pat)
        for repo in unknown {
            do {
                remember(try await provider.checkRepository(repo), accountId: account.id)
            } catch let error as ProviderError {
                if case .rateLimited = error {
                    extraRepoChecked.remove(extraRepoKey(accountId: account.id, repo: repo))
                    continue
                }
                extraRepoStatus[extraRepoKey(accountId: account.id, repo: repo)] = .problem(error.userMessage)
            } catch {
                extraRepoChecked.remove(extraRepoKey(accountId: account.id, repo: repo))
            }
        }
    }

    private func remember(_ check: RepositoryCheck, accountId: UUID) {
        let key = extraRepoKey(accountId: accountId, repo: check.name)
        extraRepoChecked.insert(key)
        extraRepoStatus[key] = check.readWithoutSignIn ? .readWithoutSignIn : nil
    }

    // MARK: - Inloggen

    /// Een provider voor een account, via het netwerk van de app.
    func provider(for account: Account, pat: String? = nil) -> any PRProvider {
        services.provider(for: account, pat: pat)
    }

    private var deviceFlow: GitHubDeviceFlow {
        GitHubDeviceFlow(config: gitHubApp, http: services.http, second: FakeGitHubTiming.deviceSecond)
    }

    /// Hoe een nieuw account standaard inlogt: GitHub via de GitHub App (als die er is),
    /// Azure DevOps via `az login`, GitLab met een personal access token (`glab` staat op minder
    /// Macs dan een token in de Keychain), Bitbucket met een API-token (iets anders is er niet).
    func defaultAuthMethod(for kind: ProviderKind) -> AuthMethod {
        switch kind {
        case .gitHub: gitHubApp.isConfigured ? .gitHubApp : .cli
        case .azureDevOps: .cli
        case .gitLab, .bitbucket: .pat
        }
    }

    func hasGitHubAppTokens(_ id: UUID) -> Bool {
        GitHubAppTokenStore(accountId: id, secrets: services.secrets).load() != nil
    }

    /// Stap 1 van inloggen met GitHub: de code die iemand op github.com intypt.
    func startGitHubSignIn() async throws -> DeviceCode {
        try await deviceFlow.start()
    }

    /// Stap 2: wacht tot de code is goedgekeurd en bewaart de tokens bij dit account.
    func finishGitHubSignIn(_ code: DeviceCode, accountId: UUID) async throws {
        let tokens = try await deviceFlow.waitForTokens(code)
        try GitHubAppTokenStore(accountId: accountId, secrets: services.secrets).save(tokens)
    }

    /// Wie er met de GitHub App is ingelogd bij dit account; nil als dat (nog) niet lukt.
    func gitHubLogin(_ accountId: UUID) async -> String? {
        let account = Account(id: accountId, kind: .gitHub, organization: "", authMethod: .gitHubApp)
        return try? await provider(for: account).currentUserId()
    }

    /// De accounts en organisaties waar de GitHub App is geïnstalleerd, eigen account eerst.
    func gitHubInstallationOwners(_ accountId: UUID) async throws -> [GitHubOwner] {
        let tokens = GitHubAppTokenSource(
            flow: deviceFlow,
            store: GitHubAppTokenStore(accountId: accountId, secrets: services.secrets)
        )
        return try await GitHubProvider(accountId: accountId, owner: "", tokenSource: tokens, http: services.http)
            .installationOwners()
    }

    func signOutOfGitHub(_ id: UUID) {
        GitHubAppTokenStore(accountId: id, secrets: services.secrets).delete()
    }

    func hasStoredPAT(_ id: UUID) -> Bool {
        (try? services.secrets.read(account: id.uuidString)) != nil
    }
}
