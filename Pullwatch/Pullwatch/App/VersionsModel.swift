import Foundation
import Observation
import PullwatchCore

nonisolated private let logger = Log(category: "app")

/// De versie- en kwetsbaarheidscheck van de gevolgde repo's: het rapport (versions.json), de
/// checks die het maken (alles, één repo, of alleen net gevolgde), de packages die je al gezien
/// hebt en de meldingen na de dagelijkse check.
@Observable
final class VersionsModel {
    private(set) var versionReport: VersionReport? {
        didSet {
            packageSummaries = versionReport?.packageSummaries() ?? []
            resetUpdateContexts()
            didChangeReport()
        }
    }
    private(set) var packageSummaries: [PackageSummary] = []
    /// Voortgang van "Afhankelijkheden checken"; `nil` als er niets loopt.
    private(set) var versionCheck: CheckProgress?
    /// Repo's (`RepoVersions.id`) die nu los opnieuw gecheckt worden.
    private(set) var refreshingRepos: Set<String> = []
    /// Per package/runtime-cyclus de nieuwste versie die je in het onderdeel Versies gezien hebt.
    private(set) var seenPackageVersions: [String: String] =
        UserDefaults.standard.dictionary(forKey: "seenPackageVersions") as? [String: String] ?? [:] {
        didSet {
            UserDefaults.standard.set(seenPackageVersions, forKey: "seenPackageVersions")
            didChangeSeenPackages()
        }
    }

    /// Na een nieuw rapport, en nadat er packages gezien zijn; `AppModel` werkt er het overzicht
    /// mee bij.
    @ObservationIgnored var didChangeReport: () -> Void = {}
    @ObservationIgnored var didChangeSeenPackages: () -> Void = {}

    /// De check over alle (of alleen de net gevolgde) repo's die nu loopt: één tegelijk, en
    /// `cancelCheck()` stopt hem.
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    /// De losse checks van één repo die nu lopen, op `RepoVersions.id`.
    @ObservationIgnored private var repoTasks: [String: Task<Void, Never>] = [:]
    /// Vroegste moment voor de volgende automatische versiecheck (na een mislukte of lopende poging).
    @ObservationIgnored private var nextAutoVersionAttempt: Date?
    /// Wat er per account gevolgd werd bij de laatste check van net gevolgde repo's.
    @ObservationIgnored private var lastFollowScope: [UUID: FilterSettings]?
    /// Repo's (`Account.repoKey`) die al een keer los gecheckt zijn, zodat een repo die steeds
    /// mislukt of niet in de lijst van de dienst staat niet elke poll opnieuw gaat.
    @ObservationIgnored private var attemptedNewRepos: Set<String> = []
    /// De metadata uit de registers van het huidige rapport, één keer gelezen, en per repo de
    /// context voor de blokkades; opnieuw bij een nieuw rapport.
    @ObservationIgnored private var registryIndex = RegistryIndex.empty
    @ObservationIgnored private var updateContexts: [String: UpdateContext] = [:]

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let accounts: AccountsModel
    @ObservationIgnored private let notifications: NotificationsModel

    init(services: AppServices, accounts: AccountsModel, notifications: NotificationsModel) {
        self.services = services
        self.accounts = accounts
        self.notifications = notifications
        do {
            versionReport = try services.versionStore.load()
        } catch {
            logger.error("versions.json onleesbaar, start leeg: \(error.localizedDescription)")
        }
        // didSet loopt niet in init.
        packageSummaries = versionReport?.packageSummaries() ?? []
        resetUpdateContexts()
    }

    private var config: AppConfig { accounts.config }

    // MARK: - Rapport lezen

    private func resetUpdateContexts() {
        registryIndex = RegistryIndex(versionReport?.packageMetadata ?? [:])
        updateContexts = [:]
    }

    /// Wat de update van een package of de oplossing van een kwetsbaarheid in `repo` tegenhoudt
    /// (`Vulnerability.fix(in:)`, `PackageInstall.update(…, context:)`).
    func updateContext(for repo: RepoVersions) -> UpdateContext {
        if let cached = updateContexts[repo.id] { return cached }
        let context = UpdateContext(repo: repo, index: registryIndex)
        updateContexts[repo.id] = context
        return context
    }

    /// De nieuwste versie van een package (`PackageUse.key`) uit het huidige rapport.
    func latestVersion(of key: String) -> String? {
        versionReport?.latestPackages[key]?.version
    }

    /// Alles wat nu in Afhankelijkheden staat telt als gezien.
    func markPackagesSeen() {
        var seen = seenPackageVersions
        for summary in packageSummaries {
            if let latest = summary.latest { seen[summary.id] = latest }
        }
        if seen != seenPackageVersions { seenPackageVersions = seen }
    }

    // MARK: - Checken

    /// Stopt de check die de balk onderin toont; repo's die al gecheckt zijn blijven.
    func cancelCheck() {
        checkTask?.cancel()
    }

    /// Eens per dag (`VersionReport.autoInterval`) vanzelf, als de instelling aan staat.
    func startAutoVersionCheckIfDue() {
        guard config.autoVersionCheck, versionCheck == nil, !config.pollableAccounts.isEmpty else { return }
        let now = Date()
        if let nextAutoVersionAttempt, now < nextAutoVersionAttempt { return }
        if let last = versionReport?.checkedAt, now.timeIntervalSince(last) < VersionReport.autoInterval { return }
        nextAutoVersionAttempt = now + VersionReport.autoRetryInterval
        startCheck(automatic: true)
    }

    /// Leest per gevolgde repo de taal- en frameworkversies, vergelijkt ze met endoflife.date en zoekt CVE's.
    /// Automatisch: een volledig mislukte check (bv. offline) overschrijft het vorige resultaat niet,
    /// en nieuwe CVE's ten opzichte van de vorige check geven een melding. Niet als er al een
    /// check loopt, ook niet een van één repo.
    func startCheck(automatic: Bool = false) {
        guard checkTask == nil, versionCheck == nil, refreshingRepos.isEmpty else { return }
        versionCheck = .starting
        checkTask = Task {
            defer {
                checkTask = nil
                versionCheck = nil
            }
            await runVersionCheck(automatic: automatic)
        }
    }

    private func runVersionCheck(automatic: Bool) async {
        let checker = services.versionChecker(metadataCache: versionReport?.packageMetadata ?? [:])
        let fresh = await checker.run(accounts: config.pollableAccounts) { @MainActor [weak self] done, total in
            self?.versionCheck = CheckProgress(done: done, total: total)
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
            save(report)
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
        lastFollowScope = NewRepoVersionCheck.scope(of: config.pollableAccounts)
        versionReport = report
        if automatic { notifyFindings(of: report, since: previous) }
        save(report)
        appendSnapshot(report)
    }

    /// Momentopname voor latere statistieken. Een onleesbaar bestand wordt niet overschreven:
    /// liever één opname missen dan de hele geschiedenis kwijt.
    private func appendSnapshot(_ report: VersionReport) {
        let store = services.versionHistoryStore
        do {
            var history = try store.load() ?? VersionHistory()
            history.append(report)
            try store.save(history)
        } catch {
            logger.error("versiegeschiedenis bijwerken mislukt: \(error.localizedDescription)")
        }
    }

    /// Checkt één repo opnieuw en vervangt alleen die regel; geen meldingen. Niet tijdens een
    /// check van alle repo's, en per repo één tegelijk.
    func startRefresh(of repo: RepoSummary) {
        guard checkTask == nil, versionCheck == nil, repoTasks[repo.id] == nil, !refreshingRepos.contains(repo.id),
              let account = config.accounts.first(where: { $0.id == repo.accountId }) else { return }
        refreshingRepos.insert(repo.id)
        repoTasks[repo.id] = Task {
            defer {
                repoTasks[repo.id] = nil
                refreshingRepos.remove(repo.id)
            }
            await runRefresh(of: repo, account: account)
        }
    }

    private func runRefresh(of repo: RepoSummary, account: Account) async {
        let checker = services.versionChecker(metadataCache: versionReport?.packageMetadata ?? [:])
        let (fresh, latest, metadata) = await checker.run(account: account, repo: repo.repo)
        guard let report = versionReport else { return }
        let updated = await checker.completingAdvisories(
            of: report.replacing(fresh, latest: latest, metadata: metadata), accounts: config.pollableAccounts
        )
        // Tijdens het opzoeken kan een andere check het rapport vervangen hebben; dan alleen de repo.
        versionReport = versionReport == report ? updated : versionReport?.replacing(fresh, latest: latest, metadata: metadata)
        save(versionReport!)
    }

    private func save(_ report: VersionReport) {
        do {
            try services.versionStore.save(report)
        } catch {
            logger.error("versions opslaan mislukt: \(error.localizedDescription)")
        }
    }

    /// Na een poll: repo's die gevolgd worden maar nog niet in het versierapport staan (net
    /// gevolgd, of nieuw bij de dienst) krijgen meteen hun check, niet pas bij de dagelijkse.
    /// Alleen met de dagelijkse check aan en als er al een rapport is (anders doet die alles).
    func startNewRepoVersionCheckIfNeeded(after result: PollResult) {
        guard config.autoVersionCheck, checkTask == nil, versionCheck == nil, refreshingRepos.isEmpty,
              let report = versionReport else { return }
        let accounts = config.pollableAccounts
        guard NewRepoVersionCheck.isNeeded(
            after: result, accounts: accounts, report: report, attempted: attemptedNewRepos, lastScope: lastFollowScope
        ) else { return }
        lastFollowScope = NewRepoVersionCheck.scope(of: accounts)
        // De balk verschijnt pas als er echt repo's te checken zijn (de eerste voortgang).
        checkTask = Task {
            defer {
                checkTask = nil
                versionCheck = nil
            }
            await runNewRepoCheck(from: report)
        }
    }

    private func runNewRepoCheck(from start: VersionReport) async {
        let checker = services.versionChecker(metadataCache: start.packageMetadata)
        let fresh = await checker.runMissing(accounts: config.pollableAccounts, in: start) { @MainActor done, total in
            self.versionCheck = CheckProgress(done: done, total: total)
        }
        attemptedNewRepos.formUnion(fresh.repos.map { Account.repoKey(accountId: $0.accountId, repo: $0.repo) })
        let repos = Task.isCancelled ? fresh.repos.filter { $0.error == nil && $0.vulnerabilityError == nil } : fresh.repos
        guard !repos.isEmpty, let report = versionReport else { return }
        logger.notice("\(repos.count) net gevolgde repo's gecheckt")
        let updated = await checker.completingAdvisories(
            of: report.replacing(repos, latest: fresh.latest, metadata: fresh.metadata), accounts: config.pollableAccounts
        )
        versionReport = versionReport == report ? updated : versionReport?.replacing(repos, latest: fresh.latest, metadata: fresh.metadata)
        save(versionReport!)
    }

    // MARK: - Meldingen

    /// Na de dagelijkse check: nieuwe kwetsbaarheden, beveiligingsmeldingen en versies, elk als de
    /// soort aan staat; boven de grens één melding per repository.
    private func notifyFindings(of report: VersionReport, since previous: VersionReport?) {
        let builder = notifications.builder
        let notifier = services.notifier
        let settings = config.notifications
        func repo(_ name: String) -> RepoVersions? { report.repos.first { $0.repo == name } }
        if settings.vulnerabilities {
            let notices = report.newVulnerabilities(since: previous).map { item in
                let v = item.vulnerability
                let advisory = report.advisory(for: v)
                let context = repo(item.repo).map(updateContext(for:)) ?? .empty
                let assessment = v.severityAssessment(advisory)
                return VulnerabilityNotice(
                    accountId: repo(item.repo)?.accountId, repo: item.repo, vulnerability: v, advisory: advisory,
                    identifiers: v.identifiers(advisory, maxAliases: 3), severityText: v.severityText(advisory),
                    severityLevel: assessment.level, severityNote: assessment.note(for: v),
                    provenance: v.provenanceLine, fixText: v.fix(in: context).plainText
                )
            }
            notifier.deliver(NotificationPlanner.capped(notices, repository: \.repository).map(builder.content(for:)))
        }
        if settings.securityAlerts {
            let notices = report.newSecurityAlerts(since: previous).map { item in
                SecurityAlertNotice(accountId: repo(item.repo)?.accountId, repo: item.repo, alert: item.alert)
            }
            notifier.deliver(NotificationPlanner.capped(notices, repository: \.repository).map(builder.content(for:)))
        }
        if settings.packageUpdates,
           let content = builder.packageUpdates(report.newPackageVersions(since: previous, onlyCanUpdateNow: settings.onlyUpdatesYouCanTake)) {
            notifier.deliver([content])
        }
    }
}
