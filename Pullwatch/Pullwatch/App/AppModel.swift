import AppKit
import Observation
import os
import PullwatchCore
import PullwatchGitHub
import PullwatchProviders
import UserNotifications

/// Log is Sendable; ook bruikbaar vanuit nonisolated callbacks.
nonisolated private let logger = Log(category: "app")

/// De vensters van de app, met hun scene-id.
enum WindowID: String {
    case main, onboarding
    /// Het Instellingen-venster (de Settings-scene, geopend met `openSettings`).
    case settings
    /// Het Over-venster.
    case about
}

/// Waarom een ingetypte of geplakte repository niet toegevoegd kan worden, in gewone woorden.
struct RepositoryInputError: Error, Equatable {
    let message: String
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
        didSet {
            // Andere bronnen uit of een account erbij of eraf: het getoonde rapport verandert mee.
            if oldValue.disabledSources != config.disabledSources || oldValue.accounts.map(\.id) != config.accounts.map(\.id) {
                recomputeVisibleReport()
            } else {
                recomputeRepoSummaries()
            }
        }
    }
    private(set) var history: History {
        didSet {
            statsCache = [:]
            recomputeRepoSummaries()
            recomputeMenu()
        }
    }
    /// Voor het menu, bijgewerkt als de geschiedenis verandert (niet bij elke keer tekenen).
    private(set) var menuPullRequests: [HistoryItem] = []
    private(set) var menuTags: [HistoryItem] = []
    private(set) var hasTags = false
    private(set) var unreadCount = 0
    private(set) var statuses: [UUID: AccountState] = [:]
    private(set) var notificationsAllowed = true
    /// Voortgang van "Opnieuw ophalen"; `nil` als er niets loopt.
    private(set) var refetch: RefetchProgress?
    /// Het bewaarde rapport (versions.json), zoals de checks het opleverden. Dit gaat als
    /// `previous` en `metadataCache` naar de volgende check; schermen tonen `visibleVersionReport`.
    private(set) var versionReport: VersionReport? {
        didSet { recomputeVisibleReport() }
    }
    /// `versionReport` zonder wat van bronnen kwam die nu uit staan
    /// (`VersionReport.visible(disabled:accountKinds:)`): wat de schermen en meldingen tonen.
    private(set) var visibleVersionReport: VersionReport?
    /// Voortgang van "Afhankelijkheden checken" (gescande repo's, totaal); `nil` als er niets loopt.
    private(set) var versionCheck: (done: Int, total: Int)?
    /// Repo's (`RepoVersions.id`) die nu los opnieuw gecheckt worden.
    private(set) var refreshingRepos: Set<String> = []
    /// Voortgang van de poll die nu loopt; nil tussen twee polls.
    private(set) var pollProgress: PollProgress?
    /// Accounts waarvan de eerste geschiedenis-sync nog moet komen (hun lijsten zijn nog leeg).
    private(set) var pendingFirstSync: Set<UUID> = []
    /// Nog geen poll afgerond sinds de start: lege lijsten zeggen dan "ophalen" in plaats van "nog geen".
    private(set) var hasPolledOnce = false
    /// Laatste poll waarin minstens één account slaagde.
    private(set) var lastSuccessfulPoll: Date?
    @ObservationIgnored private var versionTask: Task<Void, Never>?

    /// Eén status voor alles wat Pullwatch ophaalt: de balk onderin het hoofdvenster en de
    /// spinner in het menu lezen hem.
    var syncStatus: SyncStatus {
        let repoName = refreshingRepos.first.flatMap { id in repoSummariesById[id]?.repo }
        return SyncStatus.current(
            poll: pollProgress,
            firstSyncPending: !pendingFirstSync.isEmpty && !config.pollableAccounts.isEmpty,
            refetch: refetch.map { ($0.done, $0.total) },
            versions: versionCheck,
            checkingRepo: refreshingRepos.isEmpty ? nil : (repoName ?? ""),
            failure: pollFailure
        )
    }

    /// Lijsten van PR's en tags vullen zich nog: eerste start, eerste sync of opnieuw ophalen.
    var isFillingHistory: Bool {
        guard !config.pollableAccounts.isEmpty else { return false }
        return !hasPolledOnce || !pendingFirstSync.isEmpty || refetch != nil
    }

    /// Naam van het account waarvan de geschiedenis nu (of als eerste) opgehaald wordt.
    var fillingAccountName: String? {
        if let name = pollProgress?.firstSyncAccount { return name }
        let id = pendingFirstSync.first ?? config.pollableAccounts.first?.id
        return config.accounts.first { $0.id == id }?.displayName
    }

    /// Melding van het eerste account waarvan de laatste poll mislukte.
    private var pollFailure: String? {
        for account in config.accounts {
            if case .failed(let error, _) = statuses[account.id] {
                return String(localized: "\(account.displayName): \(error.userMessage)", comment: "Accountnaam, foutmelding")
            }
        }
        return nil
    }
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
    /// Gekozen onderdeel of project in de zijbalk. Het hoofdvenster onthoudt het onderdeel zelf
    /// (`@SceneStorage`) en zet het hier bij openen, als er nog niets gekozen is.
    var sidebarSelection: SidebarItem? {
        didSet {
            // Zelf iets anders kiezen begint bovenaan dat onderdeel, zonder filters van elders.
            if !isNavigating, oldValue != sidebarSelection {
                path = []
                historyTokens = []
            }
        }
    }

    /// Pagina's op de `NavigationStack` van het zichtbare onderdeel (repo-pagina, statistieken van
    /// een repo); leeg toont de lijst van het onderdeel.
    var path: [Route] = []
    /// Auteur- en repofilters op PR's of Tags vanaf een andere plek; tokens in het zoekveld.
    var historyTokens: [HistoryToken] = []
    /// Zoektekst die het onderdeel Versies bij openen overneemt (sprong vanaf een CVE).
    var packagesSearch: String?
    /// Tijdens een sprong naar een ander onderdeel blijven pad en filters van die sprong staan.
    @ObservationIgnored private var isNavigating = false

    /// Bewaard en alleen opnieuw berekend als config, geschiedenis of rapport verandert: de zijbalk,
    /// lijsten en repo-pagina lezen ze bij elke schermupdate.
    private(set) var repoSummaries: [RepoSummary] = []
    private(set) var packageSummaries: [PackageSummary] = []
    /// Zelfde als `repoSummaries`, op `RepoSummary.id`, voor pagina's die één repo tonen.
    private(set) var repoSummariesById: [String: RepoSummary] = [:]
    /// Projecten en tellers van de zijbalk.
    private(set) var sidebar = SidebarContent()
    /// Accountnamen op id, voor projectnamen die bij twee accounts voorkomen.
    private(set) var accountNames: [UUID: String] = [:]

    private func recomputeMenu() {
        let pullRequests = history.latest(.pullRequest, limit: 5)
        if pullRequests != menuPullRequests { menuPullRequests = pullRequests }
        let tags = history.latest(.tag, limit: 5)
        if tags != menuTags { menuTags = tags }
        let anyTags = history.items.contains { $0.entry.kind == .tag }
        if anyTags != hasTags { hasTags = anyTags }
        let unread = history.unreadCount
        if unread != unreadCount { unreadCount = unread }
    }

    private func recomputeVisibleReport() {
        visibleVersionReport = versionReport.map { report in
            report.visible(disabled: config.disabledSources, accountKinds: Self.accountKinds(of: report, accounts: config.accounts))
        }
        packageSummaries = visibleVersionReport?.packageSummaries() ?? []
        recomputeRepoSummaries()
    }

    /// De dienst van elk account in `report`. Een account dat niet meer in de config staat, krijgt
    /// de dienst van de beveiligingsgegevens die zijn repo's nog hebben; anders zou een uitgezette
    /// beveiligingsbron daar oude meldingen laten staan.
    nonisolated static func accountKinds(of report: VersionReport, accounts: [Account]) -> [UUID: ProviderKind] {
        var kinds = Dictionary(accounts.map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
        for repo in report.repos where kinds[repo.accountId] == nil {
            guard let feeds = repo.security?.feeds, !feeds.isEmpty else { continue }
            kinds[repo.accountId] = feeds.contains { $0.kind == .advancedSecurity } ? .azureDevOps : .gitHub
        }
        return kinds
    }

    private func recomputeRepoSummaries() {
        repoSummaries = RepoOverview.summaries(
            accounts: config.accounts, report: visibleVersionReport, history: history, packageSummaries: packageSummaries
        )
        repoSummariesById = Dictionary(repoSummaries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        recomputeSidebar()
    }

    private func recomputeSidebar() {
        let names = Dictionary(config.accounts.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        if names != accountNames { accountNames = names }
        let content = SidebarContent(
            pullRequestGroups: history.groups(.pullRequest, accountNames: names),
            tagGroups: history.groups(.tag, accountNames: names),
            repoGroups: RepoOverview.groups(repoSummaries, accountNames: names),
            badges: [
                .pullRequests: history.unreadCount(.pullRequest),
                .tags: history.unreadCount(.tag),
                .repos: repoSummaries.filter { $0.health == .problem }.count,
                .dependencies: PackageVersions.unseen(packageSummaries, seen: seenPackageVersions).count,
            ]
        )
        // Alleen bij een echte wijziging, zodat de zijbalk niet bij elke poll opnieuw tekent.
        if content != sidebar { sidebar = content }
    }

    /// Statistieken per periode en filter, bewaard tot de geschiedenis verandert of na tien
    /// minuten (de periode schuift op). Leest `history`, zodat een view die dit vraagt bijwerkt
    /// als die verandert.
    func activityStats(period: StatsPeriod, filter: ActivityFilter) -> ActivityStats {
        let history = history
        let key = StatsKey(period: period, filter: filter)
        let now = Date()
        if let cached = statsCache[key], now.timeIntervalSince(cached.at) < 600 { return cached.stats }
        let stats = ActivityStats.compute(history: history, period: period, filter: filter, now: now)
        statsCache[key] = (now, stats)
        return stats
    }

    private struct StatsKey: Hashable {
        let period: StatsPeriod
        let filter: ActivityFilter
    }

    @ObservationIgnored private var statsCache: [StatsKey: (at: Date, stats: ActivityStats)] = [:]

    /// Opent een onderdeel vanaf een andere plek (menu, melding, sprong): bovenaan, zonder filters.
    private func navigate(to section: MainSection) {
        isNavigating = true
        sidebarSelection = .section(section)
        path = []
        historyTokens = []
        isNavigating = false
    }

    /// Opent het hoofdvenster op een onderdeel.
    func show(_ section: MainSection) {
        navigate(to: section)
        show(.main)
    }

    /// Opent de pagina van een repo bovenop het zichtbare onderdeel, zodat terug weer daar uitkomt.
    func showRepo(id: String) {
        if sidebarSelection == nil { navigate(to: .repos) }
        guard path.last != .repo(id) else { return }
        path.append(.repo(id))
    }

    func showRepo(accountId: UUID, repo: String) {
        showRepo(id: repoId(accountId: accountId, repo: repo))
    }

    /// `RepoSummary.id` van een repo uit de geschiedenis (de naam kan in hoofdletters verschillen).
    func repoId(accountId: UUID, repo: String) -> String {
        repoSummaries.first { $0.accountId == accountId && $0.repo.caseInsensitiveCompare(repo) == .orderedSame }?.id
            ?? "\(accountId.uuidString)/\(repo)"
    }

    /// PR's of Tags, gefilterd op auteur en/of repo.
    func showHistory(_ kind: ItemKind, author: String? = nil, repo: HistoryRepo? = nil) {
        navigate(to: kind == .pullRequest ? .pullRequests : .tags)
        historyTokens = [author.map(HistoryToken.author), repo.map(HistoryToken.repo)].compactMap(\.self)
    }

    /// Versies, gezocht op een package.
    func showPackage(_ name: String) {
        navigate(to: .dependencies)
        packagesSearch = name
    }

    /// Statistieken van één repo, bovenop de repo-pagina.
    func showStats(repoId: String) {
        path.append(.stats(repoId: repoId))
    }

    /// ⌘[ in het menu Ga: één pagina terug op de stack van het zichtbare onderdeel.
    func goBack() {
        if !path.isEmpty { path.removeLast() }
    }

    /// ⌘R: de geopende repo opnieuw checken, in PR's, Tags en Statistieken pollen, anders alles checken.
    func refreshCurrent() {
        if case .repo(let id)? = path.last, let summary = repoSummariesById[id] {
            Task { await refreshVersions(of: summary) }
            return
        }
        switch mainSection {
        case .repos, .dependencies:
            Task { await checkVersions() }
        case .pullRequests, .tags, .stats:
            Task { await refreshNow() }
        }
    }

    /// Volgen en meldingen van één repo, als binding voor de schakelaars op de repo-pagina.
    subscript(watch repo: String, account accountId: UUID) -> WatchSet {
        get { config.accounts.first { $0.id == accountId }?.watch(for: repo) ?? .none }
        set { setWatch(newValue, repo: repo, accountId: accountId) }
    }

    /// Volgen en meldingen van één repo, direct opgeslagen; daarna meteen pollen.
    func setWatch(_ set: WatchSet, repo: String, accountId: UUID) {
        guard let index = config.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        config.accounts[index].setWatch(set, for: repo)
        saveConfig()
        Task { await refreshNow() }
    }

    /// Onderdeel van het hoofdvenster; een gekozen project hoort bij PR's, Tags of Repo's.
    var mainSection: MainSection { sidebarSelection?.section ?? .pullRequests }
    /// Per package/runtime-cyclus de nieuwste versie die je in het onderdeel Versies gezien hebt.
    private(set) var seenPackageVersions: [String: String] =
        UserDefaults.standard.dictionary(forKey: "seenPackageVersions") as? [String: String] ?? [:] {
        didSet {
            UserDefaults.standard.set(seenPackageVersions, forKey: "seenPackageVersions")
            recomputeSidebar()
        }
    }

    /// Alles wat nu in Afhankelijkheden staat telt als gezien.
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
    @ObservationIgnored private let secrets = SecretStores.shared
    /// Of config.json te lezen was; zo niet, dan ruimt `start()` geen tokens op.
    @ObservationIgnored private var configReadable = true
    @ObservationIgnored private let engine = PollEngine(
        makeProvider: { ProviderFactory.make($0, http: AppModel.networking) },
        store: JSONFileStore<SeenState>(url: AppPaths.file("seen.json"))
    )
    @ObservationIgnored private let notifier = Notifier.shared
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var refreshSoon: Task<Void, Never>?
    /// Vroegste moment voor de volgende automatische versiecheck (na een mislukte of lopende poging).
    @ObservationIgnored private var nextAutoVersionAttempt: Date?
    @ObservationIgnored private var nextUpdateCheck: Date?
    /// Sparkle, als de build een openbare sleutel heeft; anders alleen de melding met downloadknop.
    @ObservationIgnored let updater = Updater()

    private init() {
        do {
            config = try configStore.load() ?? AppConfig()
        } catch {
            logger.error("config onleesbaar: \(error.localizedDescription)")
            config = AppConfig()
            configReadable = false
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
        // In init loopt didSet niet: het menu hier één keer vullen.
        recomputeMenu()

        do {
            versionReport = try versionStore.load()
        } catch {
            logger.error("versions.json onleesbaar, start leeg: \(error.localizedDescription)")
        }
        // didSet loopt niet in init.
        recomputeVisibleReport()
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

    /// Een account kon niet gepold worden: de menubalk toont dan een waarschuwing.
    var hasPollError: Bool {
        statuses.values.contains { if case .failed = $0 { true } else { false } }
    }

    func start() {
        guard loopTask == nil else { return }
        updater.includeTestVersions = config.includeTestVersions
        updater.start()
        installsUpdatesAutomatically = updater.installsAutomatically
        notifier.onOpen = { [weak self] key in self?.markRead(key) }
        notifier.onInstallUpdate = { [weak self] in self?.installUpdate() }
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
        // Een gepauzeerd account (ingelogd, niets gevolgd) blijft staan; alleen echt lege weg.
        let incomplete = config.accounts.filter { !$0.isComplete && $0.login == nil && $0.repoWatch.isEmpty }
        for account in incomplete { removeAccount(account.id) }
        if !incomplete.isEmpty { logger.notice("\(incomplete.count) lege accounts verwijderd") }
        // Tokens van accounts die er niet meer zijn (afgebroken toevoegen, crash, oudere versie).
        // Nooit bij een onleesbare config: dan zou elk token als los gelden.
        if configReadable {
            let orphans = SecretStores.removeOrphans(keeping: Set(config.accounts.map(\.id)))
            if orphans > 0 { logger.notice("\(orphans) losse tokens uit de Keychain verwijderd") }
        }
        #if DEBUG
        // Met het nagespeelde GitHub: accounts uit een test-config krijgen een nep-token, zodat ze
        // zonder inloggen "ingelogd" zijn (schermafbeeldingen, UI-tests).
        if FakeGitHub.isEnabled {
            for account in config.accounts where account.authMethod == .gitHubApp && !hasGitHubAppTokens(account.id) {
                try? GitHubAppTokenStore(accountId: account.id, secrets: secrets)
                    .save(GitHubAppTokens(access: "fake-access", accessExpires: .distantFuture, refresh: "fake-refresh"))
            }
        }
        #endif
        // Wie al een account heeft (ook van voor het welkomstvenster) krijgt het niet te zien.
        if !onboardingCompleted && !config.pollableAccounts.isEmpty { completeOnboarding() }
        // Bij een eerste start vraagt het welkomstvenster om meldingen, met uitleg erbij;
        // anders zoals altijd bij het opstarten (macOS vraagt het maar één keer).
        if !needsOnboarding {
            Task { [weak self] in await self?.requestNotifications() }
        }

        #if DEBUG
        Task { [weak self] in
            if let self { await SnapshotTour.runIfRequested(self) }
        }
        #endif

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

    /// Stopt wat de balk onderin toont, als dat veilig kan: "Opnieuw ophalen" (accounts die nog
    /// niet aan de beurt waren houden hun oude geschiedenis-sync) of de versiecheck (repo's die al
    /// gecheckt zijn blijven).
    func cancelSync() {
        switch syncStatus.work {
        case .refetch:
            refetch = nil
            Task { await engine.cancelHistoryResync() }
        case .versions:
            versionTask?.cancel()
        default:
            break
        }
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
        guard versionCheck == nil, refreshingRepos.isEmpty else { return }
        versionCheck = (0, 0)
        let task = Task { await runVersionCheck(automatic: automatic) }
        versionTask = task
        await task.value
        versionTask = nil
        versionCheck = nil
    }

    private func runVersionCheck(automatic: Bool) async {
        let checker = VersionChecker(
            makeProvider: { ProviderFactory.make($0, http: AppModel.networking) }, http: AppModel.networking,
            metadataCache: versionReport?.packageMetadata ?? [:], disabledSources: config.disabledSources
        )
        let fresh = await checker.run(accounts: config.pollableAccounts) { done, total in
            await MainActor.run { [weak self] in self?.versionCheck = (done, total) }
        }
        if Task.isCancelled {
            // Gestopt: alleen wat helemaal gecheckt is komt in het rapport, zonder meldingen.
            let done = fresh.repos.filter { $0.error == nil && $0.vulnerabilityError == nil }
            logger.notice("versiecheck gestopt na \(done.count) repo's")
            nextAutoVersionAttempt = Date() + VersionReport.autoRetryInterval
            guard !done.isEmpty else { return }
            let report = versionReport?.replacing(done, latest: fresh.latestPackages, metadata: fresh.packageMetadata)
                ?? VersionReport(checkedAt: fresh.checkedAt, repos: done, latestPackages: fresh.latestPackages, packageMetadata: fresh.packageMetadata)
            versionReport = report
            saveVersions(report)
            return
        }
        if automatic && fresh.failedCompletely {
            logger.notice("automatische versiecheck mislukt, opnieuw over een uur")
            return
        }
        let previous = versionReport
        // GitHubs adviezen: wat de vorige check al had blijft, alleen nieuwe GHSA-ids gaan de deur uit.
        let report = await checker.completingAdvisories(
            of: fresh.carryingSeenDates(from: previous).carryingAdvisories(from: previous),
            accounts: config.pollableAccounts
        )
        // Een volledige check dekt alles wat nu gevolgd wordt.
        lastFollowScope = Dictionary(config.pollableAccounts.map { ($0.id, $0.filterSettings) }, uniquingKeysWith: { first, _ in first })
        versionReport = report
        if automatic {
            let new = report.newVulnerabilities(since: previous)
            // De meldingen tonen wat de schermen tonen: geen details van een bron die uit staat.
            if !new.isEmpty { notifier.deliverVulnerabilities(new, report: visibleVersionReport ?? report) }
            if config.notifySecurityAlerts {
                let alerts = report.newSecurityAlerts(since: previous)
                if !alerts.isEmpty { notifier.deliverSecurityAlerts(alerts) }
            }
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
        let checker = VersionChecker(
            makeProvider: { ProviderFactory.make($0, http: AppModel.networking) }, http: AppModel.networking,
            metadataCache: versionReport?.packageMetadata ?? [:], disabledSources: config.disabledSources
        )
        let (fresh, latest, metadata) = await checker.run(account: account, repo: repo.repo)
        guard let report = versionReport else {
            refreshingRepos.remove(repo.id)
            return
        }
        let updated = await checker.completingAdvisories(
            of: report.replacing(fresh, latest: latest, metadata: metadata), accounts: config.pollableAccounts
        )
        refreshingRepos.remove(repo.id)
        // Tijdens het opzoeken kan een andere check het rapport vervangen hebben; dan alleen de repo.
        versionReport = versionReport == report ? updated : versionReport?.replacing(fresh, latest: latest, metadata: metadata)
        saveVersions(versionReport!)
    }

    private func saveVersions(_ report: VersionReport) {
        do {
            try versionStore.save(report)
        } catch {
            logger.error("versions opslaan mislukt: \(error.localizedDescription)")
        }
    }

    /// Wat er per account gevolgd werd bij de laatste check van net gevolgde repo's.
    @ObservationIgnored private var lastFollowScope: [UUID: FilterSettings]?
    /// Repo's (`accountId/repo` lowercased) die al een keer los gecheckt zijn, zodat een repo die
    /// steeds mislukt of niet in de lijst van de dienst staat niet elke poll opnieuw gaat.
    @ObservationIgnored private var attemptedNewRepos: Set<String> = []

    /// Na een poll: repo's die gevolgd worden maar nog niet in het versierapport staan (net
    /// gevolgd, of nieuw bij de dienst) krijgen meteen hun check, niet pas bij de dagelijkse.
    /// Alleen met de dagelijkse check aan en als er al een rapport is (anders doet die alles).
    private func startNewRepoVersionCheckIfNeeded(after result: PollResult) {
        guard config.autoVersionCheck, versionCheck == nil, !isCheckingNewRepos, refreshingRepos.isEmpty,
              let report = versionReport else { return }
        let accounts = config.pollableAccounts
        let scope = Dictionary(accounts.map { ($0.id, $0.filterSettings) }, uniquingKeysWith: { first, _ in first })
        let known = Set(report.repos.map { "\($0.accountId.uuidString)/\($0.repo.lowercased())" })
        var seen: [(UUID, String)] = result.tagRepos.flatMap { id, repos in repos.map { (id, $0) } }
        seen += (result.syncedPullRequests + result.newPullRequests).map { ($0.accountId, $0.repo) }
        seen += result.syncedTags.map { ($0.accountId, $0.repo) }
        let unseen = seen.contains { id, repo in
            let key = "\(id.uuidString)/\(repo.lowercased())"
            guard let account = accounts.first(where: { $0.id == id }), !known.contains(key),
                  !attemptedNewRepos.contains(key) else { return false }
            let watch = account.watch(for: repo)
            return watch.prs || watch.tags || watch.completed
        }
        guard scope != lastFollowScope || unseen else { return }
        lastFollowScope = scope
        Task { await checkNewRepos() }
    }

    /// Loopt `checkNewRepos`; de balk verschijnt pas als er echt repo's te checken zijn.
    @ObservationIgnored private var isCheckingNewRepos = false

    private func checkNewRepos() async {
        guard versionCheck == nil, !isCheckingNewRepos, let start = versionReport else { return }
        isCheckingNewRepos = true
        defer { isCheckingNewRepos = false }
        let task = Task {
            let checker = VersionChecker(
                makeProvider: { ProviderFactory.make($0, http: AppModel.networking) }, http: AppModel.networking,
                metadataCache: start.packageMetadata, disabledSources: config.disabledSources
            )
            let fresh = await checker.runMissing(accounts: config.pollableAccounts, in: start) { done, total in
                await MainActor.run { [weak self] in self?.versionCheck = (done, total) }
            }
            attemptedNewRepos.formUnion(fresh.repos.map { "\($0.accountId.uuidString)/\($0.repo.lowercased())" })
            let repos = Task.isCancelled ? fresh.repos.filter { $0.error == nil && $0.vulnerabilityError == nil } : fresh.repos
            guard !repos.isEmpty, let report = versionReport else { return }
            logger.notice("\(repos.count) net gevolgde repo's gecheckt")
            let updated = await checker.completingAdvisories(
                of: report.replacing(repos, latest: fresh.latest, metadata: fresh.metadata), accounts: config.pollableAccounts
            )
            versionReport = versionReport == report ? updated : versionReport?.replacing(repos, latest: fresh.latest, metadata: fresh.metadata)
            saveVersions(versionReport!)
        }
        versionTask = task
        await task.value
        versionTask = nil
        versionCheck = nil
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

    /// Gelezen of ongelezen voor deze PR's en tags (de selectie, of alles wat een lijst toont).
    func setRead(_ ids: Set<String>, _ isRead: Bool) {
        if history.setRead(ids, isRead) { saveHistory() }
    }

    /// Bewaart een account. Een nieuw account moet af zijn (minstens één eigenaar); een bestaand
    /// mag niets volgen (gepauzeerd). False (en er verandert niets) als dat niet klopt of de PAT
    /// niet in de Keychain kon.
    @discardableResult
    func saveAccount(_ account: Account, pat: String?) -> Bool {
        let exists = config.accounts.contains { $0.id == account.id }
        guard account.isComplete || exists else { return false }
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
        scheduleRefresh()
        return true
    }

    /// Een wijziging aan een bestaand account, meteen bewaard (Instellingen hebben geen Opslaan).
    func updateAccount(_ account: Account) {
        guard let index = config.accounts.firstIndex(where: { $0.id == account.id }), config.accounts[index] != account else { return }
        config.accounts[index] = account
        saveConfig()
        scheduleRefresh()
    }

    /// De repositories die bij een account te volgen zijn (van alle eigenaren).
    func repositories(for account: Account, pat: String? = nil) async throws -> [String] {
        try await provider(for: account, pat: pat).listRepos()
    }

    /// Wat Pullwatch deze sessie over de losse repo's weet, per `extraRepoKey`: zonder inloggen
    /// gelezen, of niet (meer) gevonden. Ontbreekt: met het token, of nog niet bekeken.
    private(set) var extraRepoStatus: [String: ExtraRepoStatus] = [:]

    enum ExtraRepoStatus: Equatable {
        case readWithoutSignIn
        case problem(String)
    }

    func extraRepoKey(accountId: UUID, repo: String) -> String {
        "\(accountId.uuidString)/\(repo.lowercased())"
    }

    /// Leest wat iemand intypte of plakte en controleert de repo met één verzoek. Geeft de
    /// repo zoals de dienst hem schrijft, of een foutmelding in gewone woorden.
    func checkRepository(_ input: String, for account: Account, pat: String? = nil) async -> Result<RepositoryCheck, RepositoryInputError> {
        let repo: String
        do {
            repo = try RepositoryReference.parse(
                input, kind: account.kind, organization: account.organization,
                instanceURL: account.isGitHubEnterprise ? account.instanceURL : nil
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

    @ObservationIgnored private var extraRepoChecked: Set<String> = []

    private func remember(_ check: RepositoryCheck, accountId: UUID) {
        let key = extraRepoKey(accountId: accountId, repo: check.name)
        extraRepoChecked.insert(key)
        extraRepoStatus[key] = check.readWithoutSignIn ? .readWithoutSignIn : nil
    }

    /// Voegt een gecontroleerde losse repo toe aan een bewaard account en volgt er de PR's van.
    func addExtraRepository(_ check: RepositoryCheck, to accountId: UUID) {
        guard var account = config.accounts.first(where: { $0.id == accountId }) else { return }
        account.addExtraRepo(check.name)
        updateAccount(account)
    }

    /// Of "Volg een repository…" open moet in het hoofdvenster (menu Ga, knoppenbalk van Repo's).
    var isWatchingRepository = false

    /// Accounts waar je een losse repo aan kunt toevoegen.
    var accountsForExtraRepos: [Account] {
        config.accounts.filter { $0.isComplete && $0.kind.supportsExtraRepos }
    }

    func watchRepository() {
        guard !accountsForExtraRepos.isEmpty else { return }
        show(.main)
        isWatchingRepository = true
    }

    /// Opnieuw pollen kort na de laatste wijziging, niet bij elke klik.
    private func scheduleRefresh() {
        refreshSoon?.cancel()
        refreshSoon = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.refreshNow()
        }
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

    /// Zet een bron aan of uit (tabblad Bronnen). Er start geen check: de volgende check vraagt de
    /// bron niet meer (of weer); wat eerder van de bron kwam, staat meteen niet meer als actueel.
    func setSourceEnabled(_ id: DataSourceID, _ enabled: Bool) {
        guard config.isEnabled(id) != enabled else { return }
        if enabled {
            config.disabledSources.remove(id)
        } else {
            config.disabledSources.insert(id)
        }
        saveConfig()
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
    /// Azure DevOps via `az login`, GitLab met een personal access token (`glab` staat op minder
    /// Macs dan een token in de Keychain).
    func defaultAuthMethod(for kind: ProviderKind) -> AuthMethod {
        switch kind {
        case .gitHub: gitHubApp.isConfigured ? .gitHubApp : .cli
        case .azureDevOps: .cli
        case .gitLab: .pat
        }
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

    // MARK: Instellingen, als eigenschappen voor bindings (`@Bindable`)

    /// De keuzes voor het poll-interval, in seconden.
    static let pollIntervals = [60, 120, 300, 600, 900]

    /// Het poll-interval, op de dichtstbijzijnde keuze.
    var pollInterval: Int {
        get { Self.pollIntervals.min { abs($0 - config.clampedInterval) < abs($1 - config.clampedInterval) } ?? config.clampedInterval }
        set {
            config.pollInterval = newValue
            saveConfig()
            scheduleRefresh()
        }
    }

    var checksForUpdates: Bool {
        get { config.checkForUpdates }
        set {
            config.checkForUpdates = newValue
            saveConfig()
        }
    }

    /// Updates installeren in de app kan (Sparkle met een openbare sleutel in de build).
    var installsUpdatesInApp: Bool { updater.isEnabled }

    /// Updates vanzelf downloaden en bij het afsluiten installeren; Sparkle bewaart de keuze.
    private(set) var installsUpdatesAutomatically = false

    func setInstallsUpdatesAutomatically(_ on: Bool) {
        updater.installsAutomatically = on
        installsUpdatesAutomatically = updater.installsAutomatically
        if on, availableUpdate?.installsInApp == true { updater.downloadInBackground() }
    }

    var includesTestVersions: Bool {
        get { config.includeTestVersions }
        set {
            config.includeTestVersions = newValue
            updater.includeTestVersions = newValue
            saveConfig()
            // Een andere keuze kan een andere update geven (of geen).
            nextUpdateCheck = nil
            availableUpdate = nil
        }
    }

    var notifiesPackageUpdates: Bool {
        get { config.notifyPackageUpdates }
        set {
            config.notifyPackageUpdates = newValue
            saveConfig()
        }
    }

    var notifiesSecurityAlerts: Bool {
        get { config.notifySecurityAlerts }
        set {
            config.notifySecurityAlerts = newValue
            saveConfig()
        }
    }

    var checksVersionsDaily: Bool {
        get { config.autoVersionCheck }
        set {
            config.autoVersionCheck = newValue
            saveConfig()
        }
    }

    var historyRetention: HistoryRetention {
        get { config.historyRetention }
        set {
            config.historyRetention = newValue
            saveConfig()
            if history.prune(now: Date(), retention: newValue) { saveHistory() }
        }
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
    /// Met Sparkle uit de appcast (en met "Nu controleren" meteen Sparkle's venster); zonder
    /// sleutel uit de nieuwste release, met de DMG als download.
    func checkForUpdates(manual: Bool) async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        do {
            let update = try await findUpdate()
            availableUpdate = update
            nextUpdateCheck = Date() + UpdateChecker.interval
            if manual {
                updateCheckMessage = update.map { String(localized: "Versie \($0.version) is beschikbaar", comment: "Versienummer") }
                    ?? String(localized: "Je hebt de nieuwste versie (\(Self.currentVersion))", comment: "Huidig versienummer")
            }
            guard let update else { return }
            if update.installsInApp {
                if manual {
                    updater.installNow()
                } else if updater.installsAutomatically {
                    updater.downloadInBackground()
                }
            }
            let notifiedKey = "notifiedUpdateVersion"
            if !manual, UserDefaults.standard.string(forKey: notifiedKey) != update.version {
                UserDefaults.standard.set(update.version, forKey: notifiedKey)
                notifier.deliverUpdate(update)
            }
        } catch {
            logger.notice("updatecheck mislukt: \(error.localizedDescription)")
            if manual {
                let reason = (error as? ProviderError)?.userMessage ?? error.localizedDescription
                updateCheckMessage = String(localized: "Controleren mislukt: \(reason)", comment: "Reden waarom de updatecheck mislukte")
            }
        }
    }

    /// Met Sparkle de update uit de appcast (die Sparkle daarna zelf ook leest); zonder
    /// sleutel de nieuwste release.
    private func findUpdate() async throws -> AvailableUpdate? {
        let http = URLSessionHTTPClient()
        guard updater.isEnabled else {
            return try await UpdateChecker.check(current: Self.currentVersion, owner: updater.owner, http: http)
        }
        let feed = try await UpdateFeed.url(owner: updater.owner, includeTestVersions: config.includeTestVersions, http: http)
        updater.feedURL = feed
        let item = try await UpdateFeed.newest(
            feed: feed,
            currentBuild: Updater.currentBuild,
            includeTestVersions: config.includeTestVersions,
            system: ProcessInfo.processInfo.operatingSystemVersion,
            http: http
        )
        return item.map { AvailableUpdate($0, owner: updater.owner) }
    }

    /// De update installeren: Sparkle's venster met de release notes en Installeren.
    func installUpdate() {
        updater.installNow()
    }

    /// Lopende `tick()`s; de voortgang gaat pas weg als de laatste klaar is.
    @ObservationIgnored private var activePolls = 0

    private func tick() async {
        notificationsAllowed = await notifier.isAuthorized()
        let accounts = config.pollableAccounts
        let retention = config.historyRetention
        await refreshPendingFirstSync()
        activePolls += 1
        let result = await engine.poll(
            accounts: accounts,
            interval: TimeInterval(config.clampedInterval),
            retention: retention,
            progress: { [weak self] progress in await self?.setPollProgress(progress) }
        )
        activePolls -= 1
        if activePolls == 0 { pollProgress = nil }
        hasPolledOnce = true
        statuses = result.statuses
        await refreshPendingFirstSync()
        if result.statuses.values.contains(where: { if case .ok = $0 { true } else { false } }) {
            lastSuccessfulPoll = Date()
        }

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
        // Bestaande tags uit de eerste tag-poll van een repo: gelezen, zonder melding.
        if history.merge(syncedTags: result.syncedTags, notBefore: cutoff) { changed = true }
        // Bekende tags krijgen hun auteur en release bij, zonder melding en op hun plek.
        if history.update(tags: result.updatedTags) { changed = true }
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
        startNewRepoVersionCheckIfNeeded(after: result)
    }

    /// Accounts die nog een eerste sync moeten doen. Een account dat nu faalt (bv. uitgelogd)
    /// telt niet mee: anders blijft de balk "ophalen" zeggen tot het weer werkt.
    private func refreshPendingFirstSync() async {
        let accounts = config.pollableAccounts.filter {
            if case .failed = statuses[$0.id] { false } else { true }
        }
        let pending = await engine.pendingFirstSync(accounts: accounts, retention: config.historyRetention)
        if pending != pendingFirstSync { pendingFirstSync = pending }
    }

    private func setPollProgress(_ progress: PollProgress) {
        pollProgress = progress
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
