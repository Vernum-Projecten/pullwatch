import AppKit
import Observation
import os
import PullwatchCore
import PullwatchGitHub
import PullwatchProviders
import UserNotifications

private let logger = Log(category: "app")

/// De vensters van de app, met hun scene-id.
enum WindowID: String {
    case main, onboarding
}

/// Een verzoek om een venster te openen; elk verzoek is nieuw, ook voor hetzelfde venster.
struct WindowRequest: Equatable {
    let window: WindowID
    let id = UUID()
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var config: AppConfig {
        didSet { recomputeRepoSummaries() }
    }
    private(set) var history: History {
        didSet { recomputeRepoSummaries() }
    }
    private(set) var statuses: [UUID: AccountState] = [:]
    private(set) var notificationsAllowed = true
    /// Voortgang van "Opnieuw ophalen"; `nil` als er niets loopt.
    private(set) var refetch: RefetchProgress?
    private(set) var versionReport: VersionReport? {
        didSet {
            packageSummaries = versionReport?.packageSummaries() ?? []
            recomputeRepoSummaries()
        }
    }
    /// Voortgang van "Versies checken" (gescande repo's, totaal); `nil` als er niets loopt.
    private(set) var versionCheck: (done: Int, total: Int)?
    /// Repo's (`RepoVersions.id`) die nu los opnieuw gecheckt worden.
    private(set) var refreshingRepos: Set<String> = []
    /// Nieuwere Pullwatch op GitHub; nil als deze versie de nieuwste is (of nog niet gekeken).
    private(set) var availableUpdate: AvailableUpdate?
    /// Uitkomst van "Nu controleren" onder Instellingen; nil als er niet handmatig gekeken is.
    private(set) var updateCheckMessage: String?
    private(set) var isCheckingForUpdates = false

    /// Een venster dat open moet, als gegeven: `WindowOpener` (in het menubalk-label, dat er
    /// altijd is) opent het met `openWindow` en zet dit weer op nil.
    var windowRequest: WindowRequest?

    /// Opent een venster (en haalt de app naar voren).
    func show(_ window: WindowID) {
        windowRequest = WindowRequest(window: window)
    }

    /// Opent het hoofdvenster op een onderdeel.
    func show(_ section: MainSection) {
        mainSection = section
        show(.main)
    }

    /// Bij een eerste start opent het welkomstvenster vanzelf; niet als host van de unit-tests.
    var opensOnboardingAtLaunch: Bool { needsOnboarding && !Self.isTestHost }

    /// De app draait als host van de unit-tests: niet pollen, melden of vensters openen.
    nonisolated static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Het welkomstvenster is afgerond (of overgeslagen); daarna komt het niet vanzelf terug.
    var onboardingCompleted: Bool { config.onboardingCompleted }
    /// Eerste start: nog geen bruikbaar account en het welkomstvenster nooit afgerond.
    var needsOnboarding: Bool { !onboardingCompleted && config.pollableAccounts.isEmpty }
    /// Gekozen onderdeel van het hoofdvenster; onthouden tussen starts.
    var sidebarSelection: SidebarItem? = .section(
        UserDefaults.standard.string(forKey: "mainSection").flatMap(MainSection.init) ?? .pullRequests
    ) {
        didSet {
            // Alleen het onderdeel wordt onthouden; een project kan bij de volgende start weg zijn.
            UserDefaults.standard.set(mainSection.rawValue, forKey: "mainSection")
            if !isNavigating {
                selectedRepoId = nil
                statsRepoId = nil
                historyFilter = nil
            }
        }
    }

    /// Geopende repo in het onderdeel Repo's (`RepoSummary.id`); nil toont de lijst.
    var selectedRepoId: String?
    /// Statistieken gefilterd op één repo (`RepoSummary.id`), vanaf de repo-pagina.
    var statsRepoId: String?
    /// Tijdens een sprong naar een repo of statistieken blijft de selectie binnen het onderdeel staan.
    @ObservationIgnored private var isNavigating = false

    /// Bewaard en alleen opnieuw berekend als config, geschiedenis of rapport verandert: de zijbalk,
    /// lijsten en repo-pagina lezen ze bij elke schermupdate.
    private(set) var repoSummaries: [RepoSummary] = []
    private(set) var packageSummaries: [PackageSummary] = []

    private func recomputeRepoSummaries() {
        repoSummaries = RepoOverview.summaries(
            accounts: config.accounts, report: versionReport, history: history, packageSummaries: packageSummaries
        )
    }

    /// Opent de pagina van een repo, bv. vanuit PR's of Versies.
    func showRepo(id: String) {
        navigate(to: .repos)
        selectedRepoId = id
    }

    /// Extra filter op PR's of Tags vanaf een andere plek (auteur uit Statistieken, repo-pagina).
    var historyFilter: HistoryFilter?
    /// Zoektekst die het onderdeel Versies bij openen overneemt (sprong vanaf een CVE).
    var packagesSearch: String?
    /// Verhoogd door ⌘F; het zoekveld van het zichtbare onderdeel pakt de focus.
    var searchFocusRequest = 0

    private func navigate(to section: MainSection) {
        isNavigating = true
        sidebarSelection = .section(section)
        isNavigating = false
    }

    /// PR's of Tags, gefilterd op auteur en/of repo.
    func showHistory(_ kind: ItemKind, author: String? = nil, repo: HistoryRepo? = nil) {
        navigate(to: kind == .pullRequest ? .pullRequests : .tags)
        historyFilter = HistoryFilter(author: author, repo: repo)
    }

    /// Versies, gezocht op een package.
    func showPackage(_ name: String) {
        navigate(to: .versions)
        packagesSearch = name
    }

    /// ⌘R: de geopende repo opnieuw checken, in PR's/Tags/Statistieken pollen, anders alles checken.
    func refreshCurrent() {
        switch mainSection {
        case .repos:
            if let id = selectedRepoId, let summary = repoSummaries.first(where: { $0.id == id }) {
                Task { await refreshVersions(of: summary) }
            } else {
                Task { await checkVersions() }
            }
        case .versions:
            Task { await checkVersions() }
        case .pullRequests, .tags, .stats:
            Task { await refreshNow() }
        }
    }

    /// ⌘[ en Esc: van een repo-pagina terug naar de lijst.
    func goBack() {
        selectedRepoId = nil
    }

    /// Opent Statistieken voor één repo.
    func showStats(repoId: String) {
        navigate(to: .stats)
        statsRepoId = repoId
    }

    func showRepo(accountId: UUID, repo: String) {
        let id = repoSummaries.first { $0.accountId == accountId && $0.repo.caseInsensitiveCompare(repo) == .orderedSame }?.id
        showRepo(id: id ?? "\(accountId.uuidString)/\(repo)")
    }

    /// Volgen en meldingen van één repo, direct opgeslagen; daarna meteen pollen.
    func setWatch(_ set: WatchSet, repo: String, accountId: UUID) {
        guard let index = config.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        config.accounts[index].setWatch(set, for: repo)
        saveConfig()
        Task { await refreshNow() }
    }

    /// Onderdeel van het hoofdvenster; een gekozen project hoort bij PR's of Tags.
    var mainSection: MainSection {
        get {
            switch sidebarSelection {
            case .section(let section): section
            case .group(.pullRequest, _): .pullRequests
            case .group(.tag, _): .tags
            case .repoGroup: .repos
            case nil: .pullRequests
            }
        }
        set { sidebarSelection = .section(newValue) }
    }
    /// Per package/runtime-cyclus de nieuwste versie die je in het onderdeel Versies gezien hebt.
    private(set) var seenPackageVersions: [String: String] =
        UserDefaults.standard.dictionary(forKey: "seenPackageVersions") as? [String: String] ?? [:] {
        didSet { UserDefaults.standard.set(seenPackageVersions, forKey: "seenPackageVersions") }
    }


    /// Packages met een nieuwe versie die nog niet gezien is; teller in de zijbalk.
    var unseenPackageUpdates: Int {
        PackageVersions.unseen(packageSummaries, seen: seenPackageVersions).count
    }

    /// Alles wat nu in Versies staat telt als gezien.
    func markPackagesSeen() {
        var seen = seenPackageVersions
        for summary in packageSummaries {
            if let latest = summary.latest { seen[summary.id] = latest }
        }
        if seen != seenPackageVersions { seenPackageVersions = seen }
    }

    struct RefetchProgress: Equatable {
        let startedAt: Date
        var done: Int
        let total: Int
    }

    @ObservationIgnored private let configStore = JSONFileStore<AppConfig>(url: AppPaths.file("config.json"))
    @ObservationIgnored private let historyStore = JSONFileStore<History>(url: AppPaths.file("history.json"))
    @ObservationIgnored private let legacyRecentStore = JSONFileStore<RecentList>(url: AppPaths.file("recent.json"))
    @ObservationIgnored private let versionStore = JSONFileStore<VersionReport>(url: AppPaths.file("versions.json"))
    @ObservationIgnored private let versionHistoryStore = JSONFileStore<VersionHistory>(url: AppPaths.file("version-history.json"))
    @ObservationIgnored private let secrets = KeychainStore()
    @ObservationIgnored private let engine = PollEngine(
        makeProvider: { ProviderFactory.make($0, http: AppModel.networking) },
        store: JSONFileStore<SeenState>(url: AppPaths.file("seen.json"))
    )
    @ObservationIgnored private let notifier = Notifier.shared
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    /// Vroegste moment voor de volgende automatische versiecheck (na een mislukte of lopende poging).
    @ObservationIgnored private var nextAutoVersionAttempt: Date?
    @ObservationIgnored private var nextUpdateCheck: Date?

    private init() {
        do {
            config = try configStore.load() ?? AppConfig()
        } catch {
            logger.error("config onleesbaar: \(error.localizedDescription)")
            config = AppConfig()
        }

        var stored: History?
        var storedUnreadable = false
        do {
            stored = try historyStore.load()
        } catch {
            logger.error("history onleesbaar, start leeg: \(error.localizedDescription)")
            storedUnreadable = true
            Self.moveAside(historyStore.url)
        }
        var legacy: RecentList?
        if !storedUnreadable {
            do {
                legacy = try legacyRecentStore.load()
            } catch {
                logger.error("recent.json onleesbaar, niet gemigreerd: \(error.localizedDescription)")
            }
        }
        // recent.json blijft staan na migratie.
        let initial = History.initial(stored: stored, storedUnreadable: storedUnreadable, legacy: legacy)
        history = initial.history
        var needsSave = initial.needsSave
        if history.prune(now: Date(), retention: config.historyRetention) { needsSave = true }
        if needsSave { saveHistory() }

        do {
            versionReport = try versionStore.load()
        } catch {
            logger.error("versions.json onleesbaar, start leeg: \(error.localizedDescription)")
        }
        // didSet loopt niet in init.
        packageSummaries = versionReport?.packageSummaries() ?? []
        recomputeRepoSummaries()
    }

    /// Zet een onleesbaar bestand opzij als `<naam>.corrupt-<unix-tijd>`, zodat het niet overschreven wordt.
    private static func moveAside(_ url: URL) {
        let timestamp = Int(Date().timeIntervalSince1970)
        let target = url.deletingLastPathComponent().appending(path: "\(url.lastPathComponent).corrupt-\(timestamp)")
        do {
            try FileManager.default.moveItem(at: url, to: target)
            logger.notice("onleesbaar bestand bewaard als \(target.lastPathComponent)")
        } catch {
            logger.error("opzij zetten van \(url.lastPathComponent) mislukt: \(error.localizedDescription)")
        }
    }

    var menuBarSymbol: String {
        let hasError = statuses.values.contains { if case .failed = $0 { true } else { false } }
        return hasError ? "exclamationmark.triangle" : "arrow.triangle.pull"
    }

    func start() {
        guard loopTask == nil else { return }
        notifier.onOpen = { [weak self] key in self?.markRead(key) }
        notifier.onOpenSection = { [weak self] section in
            guard let self, let section = MainSection(rawValue: section) else { return }
            self.show(section)
        }

        wakeTask = Task { [weak self] in
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didWakeNotification) {
                // Wi-Fi is vlak na het ontwaken nog niet terug; wacht om een vals "Netwerkfout" te voorkomen.
                try? await Task.sleep(for: .seconds(10))
                await self?.refreshNow()
            }
        }

        // Lege accounts (zonder organisatie) die een oudere versie bij "+" meteen bewaarde.
        let incomplete = config.accounts.filter { !$0.isComplete }
        for account in incomplete { removeAccount(account.id) }
        if !incomplete.isEmpty { logger.notice("\(incomplete.count) lege accounts verwijderd") }
        // Wie al een account heeft (ook van voor het welkomstvenster) krijgt het niet te zien.
        if !onboardingCompleted && !config.pollableAccounts.isEmpty { completeOnboarding() }
        // Bij een eerste start vraagt het welkomstvenster om meldingen, met uitleg erbij;
        // anders zoals altijd bij het opstarten (macOS vraagt het maar één keer).
        if !needsOnboarding {
            Task { [weak self] in await self?.requestNotifications() }
        }

        loopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.tick()
                self.startAutoVersionCheckIfDue()
                self.startUpdateCheckIfDue()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    /// Haalt de geschiedenis van alle accounts opnieuw op (stil, gelezen-status blijft).
    func refetchHistory() async {
        let total = config.pollableAccounts.count
        guard total > 0 else { return }
        refetch = RefetchProgress(startedAt: Date(), done: 0, total: total)
        await engine.resetHistorySync()
        await tick()
    }

    /// Eens per dag (`VersionReport.autoInterval`) vanzelf, als de instelling aan staat.
    private func startAutoVersionCheckIfDue() {
        guard config.autoVersionCheck, versionCheck == nil, !config.pollableAccounts.isEmpty else { return }
        let now = Date()
        if let nextAutoVersionAttempt, now < nextAutoVersionAttempt { return }
        if let last = versionReport?.checkedAt, now.timeIntervalSince(last) < VersionReport.autoInterval { return }
        nextAutoVersionAttempt = now + VersionReport.autoRetryInterval
        Task { await checkVersions(automatic: true) }
    }

    /// Leest per gevolgde repo de taal- en frameworkversies, vergelijkt ze met endoflife.date en zoekt CVE's.
    /// Automatisch: een volledig mislukte check (bv. offline) overschrijft het vorige resultaat niet,
    /// en nieuwe CVE's ten opzichte van de vorige check geven een melding.
    func checkVersions(automatic: Bool = false) async {
        guard versionCheck == nil else { return }
        versionCheck = (0, 0)
        let checker = VersionChecker(makeProvider: { ProviderFactory.make($0, http: AppModel.networking) })
        let fresh = await checker.run(accounts: config.pollableAccounts) { done, total in
            await MainActor.run { [weak self] in self?.versionCheck = (done, total) }
        }
        versionCheck = nil
        if automatic && fresh.failedCompletely {
            logger.notice("automatische versiecheck mislukt, opnieuw over een uur")
            return
        }
        let previous = versionReport
        let report = fresh.carryingSeenDates(from: previous)
        versionReport = report
        if automatic {
            let new = report.newVulnerabilities(since: previous)
            if !new.isEmpty { notifier.deliverVulnerabilities(new) }
            if config.notifyPackageUpdates {
                notifier.deliverPackageUpdates(report.newPackageVersions(since: previous))
            }
        }
        do {
            try versionStore.save(report)
        } catch {
            logger.error("versions opslaan mislukt: \(error.localizedDescription)")
        }
        appendSnapshot(report)
    }

    /// Momentopname voor latere statistieken. Een onleesbaar bestand wordt niet overschreven:
    /// liever één opname missen dan de hele geschiedenis kwijt.
    private func appendSnapshot(_ report: VersionReport) {
        do {
            var history = try versionHistoryStore.load() ?? VersionHistory()
            history.append(report)
            try versionHistoryStore.save(history)
        } catch {
            logger.error("versiegeschiedenis bijwerken mislukt: \(error.localizedDescription)")
        }
    }

    /// Checkt één repo opnieuw en vervangt alleen die regel; geen meldingen.
    func refreshVersions(of repo: RepoSummary) async {
        guard versionCheck == nil, !refreshingRepos.contains(repo.id),
              let account = config.accounts.first(where: { $0.id == repo.accountId }) else { return }
        refreshingRepos.insert(repo.id)
        let (fresh, latest) = await VersionChecker(makeProvider: { ProviderFactory.make($0, http: AppModel.networking) }).run(account: account, repo: repo.repo)
        refreshingRepos.remove(repo.id)
        guard let report = versionReport else { return }
        versionReport = report.replacing(fresh, latest: latest)
        do {
            try versionStore.save(versionReport!)
        } catch {
            logger.error("versions opslaan mislukt: \(error.localizedDescription)")
        }
    }

    private func updateRefetchProgress() async {
        guard var progress = refetch else { return }
        let ids = config.pollableAccounts.map(\.id)
        let synced = await engine.lastHistorySync(for: ids)
        progress.done = synced.values.filter { $0 >= progress.startedAt }.count
        refetch = progress.done >= progress.total ? nil : progress
    }

    func refreshNow() async {
        await engine.forceRefresh()
        await tick()
    }

    /// ⌘O: wat het zichtbare onderdeel geselecteerd heeft in de browser.
    func open(_ target: BrowserTarget) {
        switch target {
        case .history(let ids):
            for item in history.items where ids.contains(item.id) { open(item) }
        case .page(let url):
            NSWorkspace.shared.open(url)
        }
    }

    func open(_ item: HistoryItem) {
        NSWorkspace.shared.open(item.entry.webURL)
        markRead(item.id)
    }

    func markRead(_ key: String) {
        history.markRead(key)
        saveHistory()
    }

    func markAllRead() {
        history.markAllRead()
        saveHistory()
    }

    /// Bewaart een volledig ingesteld account. False (en er verandert niets) als het account nog
    /// geen organisatie heeft of de PAT niet in de Keychain kon.
    @discardableResult
    func saveAccount(_ account: Account, pat: String?) -> Bool {
        guard account.isComplete else { return false }
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
        saveConfig()
        Task { await refreshNow() }
        return true
    }

    func removeAccount(_ id: UUID) {
        try? secrets.delete(account: id.uuidString)
        GitHubAppTokenStore(accountId: id, secrets: secrets).delete()
        config.accounts.removeAll { $0.id == id }
        history.removeAccount(id)
        statuses[id] = nil
        saveConfig()
        saveHistory()
    }

    func completeOnboarding() {
        guard !config.onboardingCompleted else { return }
        config.onboardingCompleted = true
        saveConfig()
    }

    /// Een account dat in een venster werd ingesteld maar niet bewaard: de inloggegevens die
    /// er al voor in de Keychain kwamen gaan weg, er komt niets in de config.
    func discardDraft(_ id: UUID) {
        guard !config.accounts.contains(where: { $0.id == id }) else { return }
        try? secrets.delete(account: id.uuidString)
        GitHubAppTokenStore(accountId: id, secrets: secrets).delete()
    }

    /// Vraagt macOS om meldingen; toont de vraag alleen de eerste keer.
    func requestNotifications() async {
        notificationsAllowed = await notifier.requestAuthorization()
    }

    func notificationStatus() async -> UNAuthorizationStatus {
        let status = await notifier.authorizationStatus()
        notificationsAllowed = status == .authorized || status == .provisional
        return status
    }

    /// De Pullwatch GitHub App uit de xcconfig; niet ingesteld = geen "Inloggen met GitHub".
    let gitHubApp = GitHubAppConfig.main

    /// Alle netwerkverkeer van de app; in debug-builds met `-PullwatchFakeGitHub` een
    /// nagespeeld GitHub (`FakeGitHub`), zodat de UI-tests de hele inlog-flow doorlopen.
    nonisolated static let networking: any HTTPClient = {
        #if DEBUG
        if FakeGitHub.isEnabled { return FakeGitHub.shared }
        #endif
        return URLSessionHTTPClient()
    }()
    var http: any HTTPClient { Self.networking }

    /// Een provider voor een account, via het netwerk van de app.
    func provider(for account: Account, pat: String? = nil) -> any PRProvider {
        ProviderFactory.make(account, pat: pat, secrets: secrets, http: http, gitHubApp: gitHubApp)
    }

    private var deviceFlow: GitHubDeviceFlow {
        GitHubDeviceFlow(config: gitHubApp, http: http, second: FakeGitHubTiming.deviceSecond)
    }

    /// Hoe een nieuw account standaard inlogt: GitHub via de GitHub App (als die er is),
    /// Azure DevOps via `az login`.
    func defaultAuthMethod(for kind: ProviderKind) -> AuthMethod {
        kind == .gitHub && gitHubApp.isConfigured ? .gitHubApp : .cli
    }

    func hasGitHubAppTokens(_ id: UUID) -> Bool {
        GitHubAppTokenStore(accountId: id, secrets: secrets).load() != nil
    }

    /// Stap 1 van inloggen met GitHub: de code die iemand op github.com intypt.
    func startGitHubSignIn() async throws -> DeviceCode {
        try await deviceFlow.start()
    }

    /// Stap 2: wacht tot de code is goedgekeurd en bewaart de tokens bij dit account.
    func finishGitHubSignIn(_ code: DeviceCode, accountId: UUID) async throws {
        let tokens = try await deviceFlow.waitForTokens(code)
        try GitHubAppTokenStore(accountId: accountId, secrets: secrets).save(tokens)
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
            store: GitHubAppTokenStore(accountId: accountId, secrets: secrets)
        )
        return try await GitHubProvider(accountId: accountId, owner: "", tokenSource: tokens, http: http)
            .installationOwners()
    }

    func signOutOfGitHub(_ id: UUID) {
        GitHubAppTokenStore(accountId: id, secrets: secrets).delete()
    }

    func hasStoredPAT(_ id: UUID) -> Bool {
        (try? secrets.read(account: id.uuidString)) != nil
    }

    func setPollInterval(_ seconds: Int) {
        config.pollInterval = seconds
        saveConfig()
        Task { await refreshNow() }
    }

    func setCheckForUpdates(_ enabled: Bool) {
        config.checkForUpdates = enabled
        saveConfig()
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Bij het opstarten en daarna eens per dag; mislukt het (offline), dan over een uur opnieuw.
    private func startUpdateCheckIfDue() {
        guard config.checkForUpdates, !isCheckingForUpdates else { return }
        if let nextUpdateCheck, Date() < nextUpdateCheck { return }
        nextUpdateCheck = Date() + 3600
        Task { await checkForUpdates(manual: false) }
    }

    /// Kijkt op GitHub naar een nieuwere release. Automatisch: één melding per nieuwe versie.
    func checkForUpdates(manual: Bool) async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        do {
            let update = try await UpdateChecker.check(current: Self.currentVersion, http: URLSessionHTTPClient())
            availableUpdate = update
            nextUpdateCheck = Date() + UpdateChecker.interval
            if manual {
                updateCheckMessage = update.map { String(localized: "Versie \($0.version) is beschikbaar") }
                    ?? String(localized: "Je hebt de nieuwste versie (\(Self.currentVersion))")
            }
            let notifiedKey = "notifiedUpdateVersion"
            if let update, !manual, UserDefaults.standard.string(forKey: notifiedKey) != update.version {
                UserDefaults.standard.set(update.version, forKey: notifiedKey)
                notifier.deliverUpdate(update)
            }
        } catch {
            logger.notice("updatecheck mislukt: \(error.localizedDescription)")
            if manual {
                let reason = (error as? ProviderError)?.userMessage ?? error.localizedDescription
                updateCheckMessage = String(localized: "Controleren mislukt: \(reason)")
            }
        }
    }

    func setNotifyPackageUpdates(_ enabled: Bool) {
        config.notifyPackageUpdates = enabled
        saveConfig()
    }

    func setAutoVersionCheck(_ enabled: Bool) {
        config.autoVersionCheck = enabled
        saveConfig()
    }

    func setHistoryRetention(_ retention: HistoryRetention) {
        config.historyRetention = retention
        saveConfig()
        if history.prune(now: Date(), retention: retention) { saveHistory() }
    }

    private func tick() async {
        notificationsAllowed = await notifier.isAuthorized()
        let result = await engine.poll(
            accounts: config.pollableAccounts,
            interval: TimeInterval(config.clampedInterval),
            retention: config.historyRetention
        )
        statuses = result.statuses

        let now = Date()
        var changed = false
        let hasNotified = !result.newPullRequests.isEmpty || !result.newTags.isEmpty
        if hasNotified {
            history.add(pullRequests: result.newPullRequests, tags: result.newTags, at: now)
            changed = true
        }
        // Na add: een gemelde PR staat dan al ongelezen in de geschiedenis en blijft dat.
        // PR's van vóór de bewaartermijn niet toevoegen: die zou prune meteen weer verwijderen.
        let cutoff = config.historyRetention.maxAge.map { now - $0 }
        if history.merge(synced: result.syncedPullRequests, notBefore: cutoff) { changed = true }
        if history.prune(now: now, retention: config.historyRetention) { changed = true }
        if changed { saveHistory() }
        let audible = NotificationPlanner.audible(
            pullRequests: result.newPullRequests,
            tags: result.newTags,
            completed: result.completedPullRequests,
            accounts: config.accounts
        )
        if !audible.pullRequests.isEmpty || !audible.tags.isEmpty || !audible.completed.isEmpty {
            notifier.deliver(NotificationPlanner.plan(
                pullRequests: audible.pullRequests,
                tags: audible.tags,
                completed: audible.completed
            ))
        }
        for id in result.authFailures {
            if let account = config.accounts.first(where: { $0.id == id }) {
                notifier.deliverAuthFailure(accountName: account.displayName)
            }
        }
        await updateRefetchProgress()
    }

    private func saveConfig() {
        do {
            try configStore.save(config)
        } catch {
            logger.error("config opslaan mislukt: \(error.localizedDescription)")
        }
    }

    private func saveHistory() {
        do {
            try historyStore.save(history)
        } catch {
            logger.error("history opslaan mislukt: \(error.localizedDescription)")
        }
    }
}

/// Filter op PR's of Tags dat vanaf een andere plek komt; staat als label boven de lijst.
struct HistoryFilter: Equatable {
    var author: String?
    var repo: HistoryRepo?
}
