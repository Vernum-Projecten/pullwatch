import Foundation
import os

private let logger = Log(category: "engine")

public enum AccountState: Equatable, Sendable {
    case idle
    case ok(lastPoll: Date)
    case failed(ProviderError, since: Date)
}

public struct PollResult: Equatable, Sendable {
    public var newPullRequests: [PullRequest] = []
    /// Nieuwe tags, en bekende tags die net een release kregen, gesorteerd op repo en dan naam.
    public var newTags: [Tag] = []
    /// Bekende tags zoals ze nu zijn (auteur, release), om de geschiedenis bij te werken. Alleen van
    /// repo's waarvan de tags deze poll echt opgehaald zijn. Niet bedoeld voor meldingen.
    public var updatedTags: [Tag] = []
    public var statuses: [UUID: AccountState] = [:]
    /// Accounts die in deze cyclus net naar `.unauthorized` gingen (één melding per overgang).
    public var authFailures: [UUID] = []
    /// PR's (alle states) uit de geschiedenis-sync, gefilterd met `PRFilter`. Leeg als er
    /// geen sync aan de beurt was of die mislukte. Niet bedoeld voor meldingen.
    public var syncedPullRequests: [PullRequest] = []
    /// PR's die sinds de vorige geschiedenis-sync gemerged zijn in repo's met "Completed" aan,
    /// gesorteerd op `closedAt`.
    public var completedPullRequests: [PullRequest] = []
    /// Bestaande tags uit de eerste tag-poll van een repo, met datum en binnen de bewaartermijn,
    /// voor de geschiedenis (gelezen). Niet bedoeld voor meldingen.
    public var syncedTags: [Tag] = []
    /// Per account de repo's waarvan deze poll de tags ophaalde (alleen als tags aan de beurt waren).
    public var tagRepos: [UUID: [String]] = [:]
    /// De checks die deze poll ophaalde, per dedupKey, om de geschiedenis bij te werken. Niet
    /// bedoeld voor meldingen.
    public var checks: [String: PRChecks] = [:]
    /// Eigen open PR's waarvan de checks net mislukten (voor de melding "Checks mislukt"); alleen
    /// met `checksForOwnPullRequests`. Een PR waarvan Pullwatch de checks nog nooit zag meldt niet.
    public var failedChecks: [PullRequest] = []
}

/// Voortgang van één `PollEngine.poll`: hoeveel accounts klaar zijn van hoeveel, en welk account
/// er een eerste geschiedenis-sync (volledige backfill) doet; nil als er geen bij zit.
public struct PollProgress: Equatable, Sendable {
    public var done: Int
    public var total: Int
    /// `Account.displayName` van het account met de eerste sync in deze poll.
    public var firstSyncAccount: String?

    public init(done: Int, total: Int, firstSyncAccount: String? = nil) {
        self.done = done
        self.total = total
        self.firstSyncAccount = firstSyncAccount
    }
}

public actor PollEngine {
    public typealias ProviderFactory = @Sendable (Account) -> any PRProvider

    /// Tags worden los van het PR-interval opgehaald, hooguit eens per kwartier.
    public static let tagInterval: TimeInterval = 900
    /// Maximaal aantal PR's per account per geschiedenis-sync.
    public static let syncLimit = 1000
    /// Een vervolg-sync kijkt zoveel terug vóór de vorige sync, zodat randgevallen niet wegvallen.
    public static let syncOverlap: TimeInterval = 3600
    /// Maximaal aantal bestaande tags per repo dat de eerste tag-poll in de geschiedenis zet.
    public static let tagBackfillLimit = 100
    /// Maximaal aantal PR's per account per poll waarvan de co-auteurs opgehaald worden; nieuwe
    /// open PR's eerst. Wat overblijft komt bij een volgende poll aan de beurt (open PR's) of
    /// zodra de PR verandert.
    public static let coAuthorLimit = 50
    /// Maximaal aantal PR's per account per poll waarvan de checks opgehaald worden.
    public static let checkLimit = 50
    /// Zo lang na de merge haalt Pullwatch de checks van een gemergde PR nog op.
    public static let recentlyMerged: TimeInterval = 3 * 86_400
    /// Mislukte checks van een open PR die niet veranderde: zo vaak opnieuw, voor een check die
    /// opnieuw gestart werd (dat verandert de PR zelf niet).
    public static let failedCheckRefresh: TimeInterval = 900
    /// Na "geen toestemming" zo lang wachten voor de volgende vraag.
    public static let checkPermissionRetry: TimeInterval = 3600

    private struct Schedule {
        var nextDue: Date = .distantPast
        var nextTagDue: Date = .distantPast
        /// Geschiedenis-sync loopt op het tag-ritme mee met een PR-poll die toch al draait.
        var nextSyncDue: Date = .distantPast
        var failures = 0
        var rateLimitedUntil: Date?
    }

    private struct Fetched {
        let userId: String
        let pullRequests: [PullRequest]
        /// `nil` als tags deze cyclus niet aan de beurt waren of het ophalen mislukte.
        let tags: [Tag]?
        /// De repo's waarvan de tags opgehaald zijn; bij tags volgen als standaard uit de lijst
        /// van de dienst.
        let tagRepos: [String]
        /// Gedateerde tags van repo's die nog niet geseed waren (`PRProvider.datedTags`).
        let backfillTags: [Tag]
        /// Tag-repo's die de provider oversloeg (404/geen toegang), lowercased.
        let unavailableTagRepos: Set<String>
        /// Tag-repo's die niet veranderden sinds hun vingerafdruk, lowercased; zonder tags.
        let unchangedTagRepos: Set<String>
        /// Nieuwe vingerafdrukken per tag-repo, lowercased.
        let tagFingerprints: [String: String]
        /// Fout bij het ophalen van tags die het account niet laat falen (zie `fetchTags`).
        let tagError: ProviderError?
        /// `nil` als de sync deze cyclus niet aan de beurt was of mislukte.
        let synced: [PullRequest]?
        /// Fout bij de geschiedenis-sync; laat het account nooit falen.
        let syncError: ProviderError?
        /// Net opgehaalde co-auteurs per dedupKey, met de revisie waarbij ze horen.
        let coAuthors: [String: (revision: String?, people: [Person])]
        /// Net opgehaalde checks per dedupKey, met de revisie waarbij ze horen.
        let checks: [String: (revision: String?, checks: PRChecks)]
    }

    /// Welke checks een poll vraagt: ook van de eigen PR's als `hideOwn` aan staat (voor de
    /// melding), met de bekende checks en het moment van de poll.
    private struct CheckRequest: Sendable {
        /// De bron CI-checks staat aan (`DataSourceID.ciChecks`); uit vraagt de poll geen checks.
        let isEnabled: Bool
        let includeOwn: Bool
        let known: [String: CheckMark]
        let at: Date
    }

    /// Waar een poll de tags van ophaalt: het account (eigen instellingen, standaard) en de repo's
    /// (lowercased) waarvan de eerste tag-poll al gedaan is, met hun vingerafdruk als die er is.
    private struct TagRepos: Sendable {
        let account: Account
        let seeded: Set<String>
        let fingerprints: [String: String]
    }

    /// Een geschiedenis-sync die deze cyclus moet draaien; `since == nil` haalt alles op.
    private struct SyncRequest: Sendable {
        let since: Date?
        /// Eerste sync over de hele bewaartermijn (geen geldige `SyncMark`).
        let isFirst: Bool
    }

    private static let maxRateLimitWait: TimeInterval = 3600

    private let makeProvider: ProviderFactory
    private let store: JSONFileStore<SeenState>?
    private let now: @Sendable () -> Date
    private var state: SeenState
    private var providers: [UUID: (account: Account, provider: any PRProvider)] = [:]
    private var userIds: [UUID: String] = [:]
    private var schedules: [UUID: Schedule] = [:]
    private var statuses: [UUID: AccountState] = [:]
    private var inFlight: Set<UUID> = []
    /// Account waarvan de eerste sync (volledige backfill) nu loopt; geldt over overlappende poll()-aanroepen heen.
    private var firstSyncAccount: UUID?
    /// Sync-markeringen van vóór "Opnieuw ophalen", per account dat nog niet opnieuw gesynct is;
    /// `cancelHistoryResync` zet ze terug.
    private var resyncBackup: [String: SyncMark] = [:]

    public init(
        makeProvider: @escaping ProviderFactory,
        store: JSONFileStore<SeenState>?,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.makeProvider = makeProvider
        self.store = store
        self.now = now
        do {
            self.state = try store?.load() ?? SeenState()
        } catch {
            logger.error("seen-state onleesbaar, start leeg: \(error.localizedDescription)")
            self.state = SeenState()
        }
    }

    /// Vergeet alle sync-markeringen en pollt meteen, zodat elk account de geschiedenis binnen de
    /// bewaartermijn opnieuw ophaalt (één account tegelijk, zoals bij de eerste sync).
    public func resetHistorySync() {
        resyncBackup = resyncBackup.merging(state.syncMarks) { kept, _ in kept }
        state.syncMarks = [:]
        forceRefresh()
    }

    /// Stopt "Opnieuw ophalen": accounts die nog niet opnieuw gesynct zijn krijgen hun vorige
    /// sync-markering terug en gaan verder met een gewone vervolg-sync. Wat al opnieuw is
    /// opgehaald (of nu loopt) blijft.
    public func cancelHistoryResync() {
        for (key, mark) in resyncBackup where state.syncMarks[key] == nil {
            state.syncMarks[key] = mark
        }
        resyncBackup = [:]
        do {
            try store?.save(state)
        } catch {
            logger.error("seen-state opslaan mislukt: \(error.localizedDescription)")
        }
    }

    /// Tijdstip van de laatste geslaagde sync per account (alleen accounts met een sync).
    public func lastHistorySync(for ids: [UUID]) -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        for id in ids {
            if let mark = state.syncMarks[id.uuidString] { result[id] = mark.at }
        }
        return result
    }

    /// Accounts waarvan de geschiedenis nog een eerste sync over de hele bewaartermijn nodig heeft
    /// (nieuw account, of andere filters of bewaartermijn); hun lijsten zijn dan nog niet gevuld.
    public func pendingFirstSync(accounts: [Account], retention: HistoryRetention) -> Set<UUID> {
        let t = now()
        return Set(accounts.filter { syncRequest(for: $0, retention: retention, at: t).isFirst }.map(\.id))
    }

    public func forceRefresh() {
        let t = now()
        for (id, var schedule) in schedules {
            if let until = schedule.rateLimitedUntil, until > t { continue }
            schedule.nextDue = t
            schedule.nextTagDue = t
            schedule.nextSyncDue = t
            schedules[id] = schedule
        }
    }

    public func poll(
        accounts: [Account],
        interval: TimeInterval,
        retention: HistoryRetention,
        checksForOwnPullRequests: Bool = false,
        fetchChecks: Bool = true,
        progress: (@Sendable (PollProgress) async -> Void)? = nil
    ) async -> PollResult {
        let t = now()
        forget(except: Set(accounts.map(\.id)))

        // Hooguit één eerste sync (volledige backfill) tegelijk, ook als poll() overlapt (bv. "Nu
        // verversen" naast de timer), zodat de backfills van meerdere accounts niet samen de
        // zoek-ratelimit opmaken. Andere accounts houden hun `nextSyncDue` en komen later aan de
        // beurt; vervolg-syncs lopen gewoon mee.
        let jobs = accounts
            .filter { !inFlight.contains($0.id) && (schedules[$0.id]?.nextDue ?? .distantPast) <= t }
            .map { account in
                let tagsDue = (schedules[account.id]?.nextTagDue ?? .distantPast) <= t
                let syncDue = (schedules[account.id]?.nextSyncDue ?? .distantPast) <= t
                var sync = syncDue ? syncRequest(for: account, retention: retention, at: t) : nil
                if let request = sync, request.isFirst {
                    if firstSyncAccount == nil { firstSyncAccount = account.id } else { sync = nil }
                }
                let prefix = "\(account.id.uuidString):"
                return (
                    account: account,
                    provider: provider(for: account),
                    userId: userIds[account.id],
                    coAuthorRevisions: state.coAuthors.filter { $0.key.hasPrefix(prefix) }.mapValues(\.revision),
                    checkRequest: CheckRequest(
                        isEnabled: fetchChecks,
                        includeOwn: checksForOwnPullRequests,
                        known: state.checks.filter { $0.key.hasPrefix(prefix) },
                        at: t
                    ),
                    tagRepos: TagRepos(
                        account: account,
                        seeded: Set(state.tagSeeded.keys.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }),
                        fingerprints: Dictionary(uniqueKeysWithValues: state.tagFingerprints
                            .filter { $0.key.hasPrefix(prefix) }
                            .map { (String($0.key.dropFirst(prefix.count)), $0.value) })
                    ),
                    fetchTags: tagsDue && (account.followsTagsByDefault || !account.tagRepos.isEmpty),
                    sync: sync
                )
            }
        // Markeer vóór de eerste suspensie, zodat overlappende poll()-aanroepen deze accounts overslaan.
        for job in jobs { inFlight.insert(job.account.id) }
        let jobsById = Dictionary(uniqueKeysWithValues: jobs.map { ($0.account.id, $0) })
        var report = PollProgress(
            done: 0, total: jobs.count,
            firstSyncAccount: jobs.first { $0.sync?.isFirst == true }?.account.displayName
        )
        if !jobs.isEmpty { await progress?(report) }

        var result = PollResult()
        var succeeded: [UUID] = []
        await withTaskGroup(of: (UUID, Result<Fetched, ProviderError>).self) { group in
            for job in jobs {
                group.addTask {
                    (job.account.id, await Self.fetch(
                        job.provider,
                        knownUserId: job.userId,
                        coAuthorRevisions: job.coAuthorRevisions,
                        checkRequest: job.checkRequest,
                        tagRepos: job.tagRepos,
                        fetchTags: job.fetchTags,
                        sync: job.sync
                    ))
                }
            }
            // Pas elk resultaat direct toe zodra het binnenkomt (actor-geïsoleerd).
            for await (id, outcome) in group {
                guard let job = jobsById[id] else { continue }
                switch outcome {
                case .success(let fetched):
                    let checks = handleChecks(fetched, includeOwn: checksForOwnPullRequests, at: t)
                    result.checks.merge(checks.all) { _, new in new }
                    result.failedChecks += checks.failed
                    let fresh = handleSuccess(job.account, fetched, retention: retention, at: t, interval: interval)
                    result.newPullRequests += fresh.pullRequests
                    result.newTags += fresh.tags
                    result.updatedTags += fresh.updated
                    result.syncedTags += fresh.backfill
                    if fetched.tags != nil { result.tagRepos[id] = fetched.tagRepos }
                    let sync = handleSync(job.account, fetched, request: job.sync, retention: retention, at: t)
                    result.syncedPullRequests += sync.pullRequests
                    result.completedPullRequests += sync.completed
                    succeeded.append(id)
                case .failure(let error):
                    if await handleFailure(job.account, job.provider, error, at: t, interval: interval) {
                        result.authFailures.append(id)
                    }
                }
                inFlight.remove(id)
                if firstSyncAccount == id { firstSyncAccount = nil }
                report.done += 1
                await progress?(report)
            }
        }

        // Alleen accounts die nu slaagden prunen: een langdurig falend account mag zijn seen niet kwijtraken.
        state.prune(now: t, onlyKeyPrefixes: succeeded.map { "\($0.uuidString):" })
        do {
            try store?.save(state)
        } catch {
            logger.error("seen-state opslaan mislukt: \(error.localizedDescription)")
        }

        result.newPullRequests.sort { $0.createdAt < $1.createdAt }
        result.newTags.sort { ($0.repo, $0.name) < ($1.repo, $1.name) }
        result.updatedTags.sort { ($0.repo, $0.name) < ($1.repo, $1.name) }
        result.syncedTags.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        result.completedPullRequests.sort { ($0.closedAt ?? .distantPast) < ($1.closedAt ?? .distantPast) }
        result.failedChecks.sort { $0.createdAt < $1.createdAt }
        result.statuses = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, statuses[$0.id] ?? .idle) })
        return result
    }

    private static func fetch(
        _ provider: any PRProvider,
        knownUserId: String?,
        coAuthorRevisions: [String: String?],
        checkRequest: CheckRequest,
        tagRepos: TagRepos,
        fetchTags: Bool,
        sync: SyncRequest?
    ) async -> Result<Fetched, ProviderError> {
        do {
            let userId: String
            if let knownUserId {
                userId = knownUserId
            } else {
                userId = try await provider.currentUserId()
            }
            let pullRequests = try await provider.openPullRequests()
            var tags = TagOutcome(repos: tagRepos.account.tagRepos)
            if fetchTags {
                tags = try await Self.fetchTags(provider, tagRepos)
            }
            var synced: [PullRequest]?
            var syncError: ProviderError?
            if let sync {
                (synced, syncError) = await Self.fetchSync(provider, since: sync.since)
            }
            let details = await Self.fetchDetails(
                provider,
                open: pullRequests,
                synced: synced ?? [],
                settings: tagRepos.account.filterSettings,
                userId: userId,
                coAuthorRevisions: coAuthorRevisions,
                checks: checkRequest
            )
            return .success(Fetched(
                userId: userId,
                pullRequests: pullRequests,
                tags: tags.fetch?.tags,
                tagRepos: tags.repos,
                backfillTags: tags.backfill,
                unavailableTagRepos: Set((tags.fetch?.unavailableRepos ?? []).map { $0.lowercased() }),
                unchangedTagRepos: Set((tags.fetch?.unchangedRepos ?? []).map { $0.lowercased() }),
                tagFingerprints: Dictionary(
                    (tags.fetch?.fingerprints ?? [:]).map { ($0.key.lowercased(), $0.value) },
                    uniquingKeysWith: { first, _ in first }
                ),
                tagError: tags.error,
                synced: synced,
                syncError: syncError,
                coAuthors: details.coAuthors,
                checks: details.checks
            ))
        } catch let error as ProviderError {
            return .failure(error)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    /// Uitkomst van het ophalen van tags in één poll.
    private struct TagOutcome {
        var fetch: TagFetch?
        var repos: [String]
        var backfill: [Tag] = []
        var error: ProviderError?
    }

    /// Haalt de tags op van de eigen tag-repo's, en bij tags als standaard van alle repo's in de
    /// lijst van de dienst. Een geseede repo met een vingerafdruk wordt alleen helemaal opgehaald
    /// als die veranderde (`tags(in:unchanged:)`). Repo's die nog niet geseed zijn krijgen hun
    /// gedateerde tags erbij: uit de opgehaalde tags als die al een datum hebben, anders via
    /// `datedTags`; lukt dat niet, dan seedt die repo stil zoals vroeger.
    /// Alleen `.rateLimited` laat het account falen; andere tag-fouten (ook `.unauthorized`,
    /// bv. een 403 op één repo) worden teruggegeven zodat de PR's van deze poll gewoon verwerkt worden.
    private static func fetchTags(
        _ provider: any PRProvider,
        _ tagRepos: TagRepos
    ) async throws -> TagOutcome {
        let account = tagRepos.account
        var outcome = TagOutcome(repos: account.tagRepos)
        do {
            if account.followsTagsByDefault {
                outcome.repos = account.tagRepos(available: try await provider.listRepos())
            }
            var unchanged: [String: String] = [:]
            for repo in outcome.repos {
                let key = repo.lowercased()
                if tagRepos.seeded.contains(key), let fingerprint = tagRepos.fingerprints[key] {
                    unchanged[repo] = fingerprint
                }
            }
            let fetch = try await provider.tags(in: outcome.repos, unchanged: unchanged)
            outcome.fetch = fetch
            let unavailable = Set(fetch.unavailableRepos.map { $0.lowercased() })
            let fetchedByRepo = Dictionary(grouping: fetch.tags) { $0.repo.lowercased() }
            for repo in outcome.repos {
                let key = repo.lowercased()
                guard !tagRepos.seeded.contains(key), !unavailable.contains(key) else { continue }
                let dated = (fetchedByRepo[key] ?? []).filter { $0.createdAt != nil }
                if !dated.isEmpty {
                    outcome.backfill += dated.sorted { $0.createdAt! > $1.createdAt! }.prefix(tagBackfillLimit)
                    continue
                }
                do {
                    outcome.backfill += try await provider.datedTags(in: repo, limit: tagBackfillLimit)
                } catch {
                    logger.notice("tagdatums ophalen mislukt voor \(repo): \(error.localizedDescription)")
                }
            }
            return outcome
        } catch let error as ProviderError {
            switch error {
            case .rateLimited: throw error
            default:
                outcome.error = error
                return outcome
            }
        } catch {
            outcome.error = .network(error.localizedDescription)
            return outcome
        }
    }

    /// Haalt in één keer (`PRProvider.details`, bij GitHub in dezelfde GraphQL-verzoeken) de
    /// co-auteurs en de checks op. Co-auteurs: van de zichtbare PR's die nieuw zijn of veranderden
    /// sinds de vorige keer (`PullRequest.revision`), hooguit `coAuthorLimit`. Checks: zie
    /// `checksVisible` en `wantsChecks`, hooguit `checkLimit`. Open PR's eerst, dan de gesyncte,
    /// elk nieuwste eerst. Een PR die niet veranderde kost geen verzoek. Fouten laten het account
    /// niet falen; die PR's komen bij een volgende poll opnieuw aan de beurt.
    private static func fetchDetails(
        _ provider: any PRProvider,
        open: [PullRequest],
        synced: [PullRequest],
        settings: FilterSettings,
        userId: String,
        coAuthorRevisions known: [String: String?],
        checks request: CheckRequest
    ) async -> (coAuthors: [String: (revision: String?, people: [Person])], checks: [String: (revision: String?, checks: PRChecks)]) {
        let candidates = open.sorted { $0.createdAt > $1.createdAt } + synced.sorted { $0.createdAt > $1.createdAt }
        var seen: Set<String> = []
        let forCoAuthors = Array(candidates
            .filter { pr in
                guard seen.insert(pr.dedupKey).inserted,
                      PRFilter.passes(pr, settings: settings, currentUserId: userId) else { return false }
                guard let revision = known[pr.dedupKey] else { return true }
                return revision != pr.revision
            }
            .prefix(coAuthorLimit))
        seen = []
        let forChecks = !request.isEnabled ? [] : Array(candidates
            .filter { pr in
                guard seen.insert(pr.dedupKey).inserted,
                      checksVisible(pr, settings: settings, userId: userId, includeOwn: request.includeOwn, at: request.at)
                else { return false }
                return wantsChecks(pr, mark: request.known[pr.dedupKey], at: request.at)
            }
            .prefix(checkLimit))
        guard !forCoAuthors.isEmpty || !forChecks.isEmpty else { return ([:], [:]) }
        var wanted: [PullRequest] = []
        var keys: Set<String> = []
        for pr in forCoAuthors + forChecks where keys.insert(pr.dedupKey).inserted { wanted.append(pr) }
        do {
            let found = try await provider.details(
                of: wanted,
                coAuthorsOf: Set(forCoAuthors.map(\.dedupKey)),
                checksOf: Set(forChecks.map(\.dedupKey))
            )
            var coAuthors: [String: (revision: String?, people: [Person])] = [:]
            for pr in forCoAuthors {
                coAuthors[pr.dedupKey] = (pr.revision, found.coAuthors[pr.dedupKey] ?? [])
            }
            var checks: [String: (revision: String?, checks: PRChecks)] = [:]
            for pr in forChecks {
                if let value = found.checks[pr.dedupKey] { checks[pr.dedupKey] = (pr.revision, value) }
            }
            return (coAuthors, checks)
        } catch {
            logger.notice("co-auteurs en checks ophalen mislukt: \(error.localizedDescription)")
            return ([:], [:])
        }
    }

    /// Of de checks van deze PR in Pullwatch te zien zijn of gemeld worden: een open PR die de
    /// lijst toont, of een eigen open PR in een gevolgde repo als de melding aan staat; een
    /// gemergde PR alleen kort na de merge (`recentlyMerged`).
    private static func checksVisible(
        _ pr: PullRequest, settings: FilterSettings, userId: String, includeOwn: Bool, at t: Date
    ) -> Bool {
        switch pr.state {
        case .open:
            if PRFilter.passes(pr, settings: settings, currentUserId: userId) { return true }
            return includeOwn && isOwn(pr, userId: userId) && settings.watch(for: pr.repo).prs
        case .merged:
            guard let closedAt = pr.closedAt, t.timeIntervalSince(closedAt) <= recentlyMerged else { return false }
            return PRFilter.passes(pr, settings: settings, currentUserId: userId)
        case .closed:
            return false
        }
    }

    private static func isOwn(_ pr: PullRequest, userId: String) -> Bool {
        pr.authorId.caseInsensitiveCompare(userId) == .orderedSame
    }

    /// Moeten de checks van deze PR (opnieuw) opgehaald worden? Nog nooit opgehaald, de PR
    /// veranderde (een push), of de checks lopen nog. Mislukte checks van een open PR af en toe
    /// opnieuw (`failedCheckRefresh`), omdat iemand ze opnieuw kan starten zonder dat de PR
    /// verandert; groene checks van een PR die niet veranderde nooit. Na "geen toestemming"
    /// eens per `checkPermissionRetry`.
    static func wantsChecks(_ pr: PullRequest, mark: CheckMark?, at t: Date) -> Bool {
        guard let mark else { return true }
        if mark.revision != pr.revision { return true }
        switch mark.checks {
        case .needsPermission:
            return t.timeIntervalSince(mark.fetchedAt) >= checkPermissionRetry
        case .counts(let counts):
            switch counts.state {
            case .pending: return true
            case .failed: return pr.state == .open && t.timeIntervalSince(mark.fetchedAt) >= failedCheckRefresh
            case .passed, nil: return false
            }
        }
    }

    /// Fouten (ook `.rateLimited` en `.unauthorized`) worden teruggegeven, nooit gegooid:
    /// de geschiedenis-sync mag het account niet laten falen.
    private static func fetchSync(
        _ provider: any PRProvider,
        since: Date?
    ) async -> (pullRequests: [PullRequest]?, error: ProviderError?) {
        do {
            return (try await provider.pullRequests(updatedSince: since, limit: syncLimit), nil)
        } catch let error as ProviderError {
            return (nil, error)
        } catch {
            return (nil, .network(error.localizedDescription))
        }
    }

    /// Vervolg-sync vanaf de vorige sync (min overlap), mits de sync-relevante filtersettings en
    /// de bewaartermijn ongewijzigd zijn; anders een eerste sync over de hele bewaartermijn.
    private func syncRequest(for account: Account, retention: HistoryRetention, at t: Date) -> SyncRequest {
        if let mark = state.syncMarks[account.id.uuidString],
           mark.settings.sameSyncScope(as: account.filterSettings), mark.retention == retention {
            return SyncRequest(since: mark.at - Self.syncOverlap, isFirst: false)
        }
        return SyncRequest(since: retention.maxAge.map { t - $0 }, isFirst: true)
    }

    private func provider(for account: Account) -> any PRProvider {
        if let cached = providers[account.id], cached.account == account {
            return cached.provider
        }
        let provider = makeProvider(account)
        providers[account.id] = (account, provider)
        userIds[account.id] = nil
        return provider
    }

    private func forget(except ids: Set<UUID>) {
        providers = providers.filter { ids.contains($0.key) }
        userIds = userIds.filter { ids.contains($0.key) }
        schedules = schedules.filter { ids.contains($0.key) }
        statuses = statuses.filter { ids.contains($0.key) }
        let keys = Set(ids.map(\.uuidString))
        state.lastSettings = state.lastSettings.filter { keys.contains($0.key) }
        state.syncMarks = state.syncMarks.filter { keys.contains($0.key) }
        resyncBackup = resyncBackup.filter { keys.contains($0.key) }
        state.retain(onlyKeyPrefixes: keys.map { "\($0):" })
    }

    /// Bewaart de opgehaalde checks en geeft ze terug voor de geschiedenis, met de eigen open
    /// PR's waarvan de checks net rood werden: van lopend of groen naar mislukt, of mislukt op
    /// een nieuwe commit. Een PR waarvan de checks nog nooit opgehaald waren meldt niet, zodat de
    /// eerste poll na het aanzetten stil blijft.
    private func handleChecks(
        _ fetched: Fetched,
        includeOwn: Bool,
        at t: Date
    ) -> (all: [String: PRChecks], failed: [PullRequest]) {
        var all: [String: PRChecks] = [:]
        var failed: [PullRequest] = []
        let open = Dictionary(fetched.pullRequests.map { ($0.dedupKey, $0) }, uniquingKeysWith: { first, _ in first })
        for (key, found) in fetched.checks {
            let previous = state.checks[key]
            state.checks[key] = CheckMark(revision: found.revision, checks: found.checks, fetchedAt: t, at: t)
            all[key] = found.checks
            guard includeOwn, found.checks.state == .failed, let previous,
                  previous.checks.state != .failed || previous.revision != found.revision,
                  var pr = open[key], Self.isOwn(pr, userId: fetched.userId) else { continue }
            pr.checks = found.checks
            failed.append(pr)
        }
        for pr in fetched.pullRequests + (fetched.synced ?? []) {
            state.checks[pr.dedupKey]?.at = t
        }
        return (all, failed)
    }

    private func handleSuccess(
        _ account: Account,
        _ fetched: Fetched,
        retention: HistoryRetention,
        at t: Date,
        interval: TimeInterval
    ) -> (pullRequests: [PullRequest], tags: [Tag], updated: [Tag], backfill: [Tag]) {
        let settings = account.filterSettings
        let key = account.id.uuidString
        let previous = state.lastSettings[key].flatMap { $0.sameSource(as: settings) ? $0 : nil }
        for (dedupKey, found) in fetched.coAuthors {
            state.coAuthors[dedupKey] = CoAuthorMark(revision: found.revision, people: found.people, at: t)
        }
        for pr in fetched.pullRequests + (fetched.synced ?? []) {
            state.coAuthors[pr.dedupKey]?.at = t
        }

        var fresh: [PullRequest] = []
        for pr in fetched.pullRequests.map(withDetails)
        where PRFilter.passes(pr, settings: settings, currentUserId: fetched.userId) {
            // Alleen melden als de PR onder de vorige settings ook zichtbaar was; anders is hij
            // pas zichtbaar door een instellingswijziging of eerste poll → stil seeden.
            if !state.contains(pr.dedupKey), let previous, previous.covers(repo: pr.repo),
               PRFilter.passes(pr, settings: previous, currentUserId: fetched.userId) {
                fresh.append(pr)
            }
            state.mark(pr.dedupKey, at: t)
        }

        state.lastSettings[key] = settings
        userIds[account.id] = fetched.userId
        let previousSchedule = schedules[account.id] ?? Schedule()
        var schedule = Schedule(
            nextDue: t + interval,
            nextTagDue: previousSchedule.nextTagDue,
            nextSyncDue: previousSchedule.nextSyncDue
        )
        if fetched.tags != nil || fetched.tagError != nil {
            schedule.nextTagDue = t + Self.tagInterval
        }
        if let tagError = fetched.tagError {
            logger.warning("tags ophalen mislukt voor \(account.displayName): \(tagError.userMessage)")
        }
        schedules[account.id] = schedule
        statuses[account.id] = .ok(lastPoll: t)
        let tags = handleTags(account, fetched, notBefore: retention.maxAge.map { t - $0 }, at: t)
        return (fresh, tags.fresh, tags.updated, tags.backfill)
    }

    /// Verwerkt de geschiedenis-sync: plant de volgende sync en geeft de gefilterde PR's terug,
    /// plus de PR's die sinds de vorige sync gemerged zijn (zie `completed`). Markeert geen
    /// PR-dedupKeys in `seen`; meldingen van nieuwe PR's blijven bij de open-PR-poll.
    private func handleSync(
        _ account: Account,
        _ fetched: Fetched,
        request: SyncRequest?,
        retention: HistoryRetention,
        at t: Date
    ) -> (pullRequests: [PullRequest], completed: [PullRequest]) {
        var schedule = schedules[account.id] ?? Schedule()
        defer { schedules[account.id] = schedule }

        if let error = fetched.syncError {
            // `syncMarks` ongemoeid: na een mislukte eerste sync volgt weer een eerste sync.
            if case .rateLimited(let until) = error {
                schedule.nextSyncDue = min(until, t + Self.maxRateLimitWait)
            } else {
                schedule.nextSyncDue = t + Self.tagInterval
            }
            logger.warning("geschiedenis-sync mislukt voor \(account.displayName): \(error.userMessage)")
            return ([], [])
        }
        guard let synced = fetched.synced else { return ([], []) }

        let settings = account.filterSettings
        // Een eerste sync seedt stil: dan is er geen vorige sync om tegen te vergelijken.
        let previous = request?.isFirst == false ? state.syncMarks[account.id.uuidString] : nil
        let newlyCompleted = completed(account, synced, previous: previous, userId: fetched.userId, at: t)
        state.syncMarks[account.id.uuidString] = SyncMark(at: t, settings: settings, retention: retention)
        resyncBackup[account.id.uuidString] = nil
        schedule.nextSyncDue = t + Self.tagInterval
        return (
            synced.filter { PRFilter.passes($0, settings: settings, currentUserId: fetched.userId) }.map(withDetails),
            newlyCompleted.map(withDetails)
        )
    }

    /// De PR met de bewaarde co-auteurs en checks erbij, als die er zijn. Checks van een oudere
    /// revisie horen niet meer bij deze PR en blijven weg.
    private func withDetails(_ pr: PullRequest) -> PullRequest {
        var pr = pr
        if let people = state.coAuthors[pr.dedupKey]?.people, !people.isEmpty {
            pr.coAuthors = people
        }
        if let mark = state.checks[pr.dedupKey], mark.revision == pr.revision {
            pr.checks = mark.checks
        }
        return pr
    }

    /// Gemergde PR's in repo's met "Completed" aan die gemeld moeten worden: de repo had het ook
    /// al bij de vorige sync aan (aanzetten seedt stil), de merge is van na die sync (min overlap)
    /// en de PR is nog niet gemeld. Alle gemergde PR's worden als gezien gemarkeerd.
    private func completed(
        _ account: Account,
        _ synced: [PullRequest],
        previous: SyncMark?,
        userId: String,
        at t: Date
    ) -> [PullRequest] {
        let settings = account.filterSettings
        var fresh: [PullRequest] = []
        for pr in synced where pr.state == .merged
            && PRFilter.passes(pr, settings: settings, currentUserId: userId, watching: \.completed) {
            let key = pr.dedupKey + ":completed"
            if let previous, !state.contains(key), previous.settings.covers(repo: pr.repo),
               PRFilter.passes(pr, settings: previous.settings, currentUserId: userId, watching: \.completed),
               let closedAt = pr.closedAt, closedAt >= previous.at - Self.syncOverlap {
                fresh.append(pr)
            }
            state.mark(key, at: t)
        }
        return fresh
    }

    /// Eerste tag-poll per repo meldt niets: de bestaande tags met een datum vanaf `notBefore`
    /// (de bewaartermijn) gaan als `backfill` stil de geschiedenis in. Daarna wordt elke
    /// onbekende tag gemeld, en een bekende tag die een release krijgt ook (één keer). Releases
    /// die er al waren toen een repo voor het eerst met vingerafdruk opgehaald werd (de eerste
    /// poll na een update) gaan stil. Bekende tags komen in `updated`, voor auteur en release in
    /// de geschiedenis.
    private func handleTags(
        _ account: Account,
        _ fetched: Fetched,
        notBefore: Date?,
        at t: Date
    ) -> (fresh: [Tag], updated: [Tag], backfill: [Tag]) {
        // Mislukte tag-fetch: tag-state ongemoeid laten tot de volgende tag-poll.
        guard fetched.tagError == nil else { return ([], [], []) }
        let prefix = "\(account.id.uuidString):"
        // Repo's waarvan tags uit staan vergeten, zodat weer aanzetten opnieuw stil seedt.
        let wantedKeys = Set(fetched.tagRepos.map { prefix + $0.lowercased() })
        state.tagSeeded = state.tagSeeded.filter { !$0.key.hasPrefix(prefix) || wantedKeys.contains($0.key) }
        state.dropOrphanFingerprints()

        guard let tags = fetched.tags else { return ([], [], []) }
        let tagsByRepo = Dictionary(grouping: tags) { $0.repo.lowercased() }
        let datedByRepo = Dictionary(grouping: fetched.backfillTags) { $0.repo.lowercased() }
        if !fetched.unavailableTagRepos.isEmpty {
            logger.warning("tags overgeslagen voor \(account.displayName): \(fetched.unavailableTagRepos.sorted().joined(separator: ", ")) (niet gevonden of geen toegang)")
        }
        var fresh: [Tag] = []
        var updated: [Tag] = []
        var backfill: [Tag] = []
        // Onbereikbare repo's niet als geseed markeren of verversen: anders worden hun bestaande
        // tags als nieuw gemeld zodra de toegang terugkomt.
        for repo in Set(fetched.tagRepos.map { $0.lowercased() }).subtracting(fetched.unavailableTagRepos) {
            let seededKey = prefix + repo
            let isSeeded = state.tagSeeded[seededKey] != nil
            if isSeeded, fetched.unchangedTagRepos.contains(repo) {
                state.refreshTags(ofRepo: seededKey, at: t)
                state.tagSeeded[seededKey] = t
                continue
            }
            let knowsReleases = state.tagFingerprints[seededKey] != nil
            for tag in tagsByRepo[repo] ?? [] {
                let releaseKey = tag.dedupKey + ":release"
                if isSeeded, !state.contains(tag.dedupKey) {
                    fresh.append(tag)
                } else if isSeeded, knowsReleases, tag.release != nil, !state.contains(releaseKey) {
                    fresh.append(tag) // de tag was er al, de release is nieuw
                } else if isSeeded {
                    updated.append(tag)
                }
                state.mark(tag.dedupKey, at: t)
                if tag.release != nil { state.mark(releaseKey, at: t) }
            }
            // Ook tags buiten wat de provider teruggaf (bv. voorbij de nieuwste honderd) blijven gezien.
            state.refreshTags(ofRepo: seededKey, at: t)
            state.tagFingerprints[seededKey] = fetched.tagFingerprints[repo]
            if !isSeeded {
                for tag in datedByRepo[repo] ?? [] {
                    guard let date = tag.createdAt, notBefore.map({ date >= $0 }) ?? true else { continue }
                    backfill.append(tag)
                    state.mark(tag.dedupKey, at: t)
                    if tag.release != nil { state.mark(tag.dedupKey + ":release", at: t) }
                }
            }
            state.tagSeeded[seededKey] = t
        }
        return (fresh, updated, backfill)
    }

    /// Geeft `true` als het account net naar `.unauthorized` is overgegaan.
    private func handleFailure(
        _ account: Account,
        _ provider: any PRProvider,
        _ error: ProviderError,
        at t: Date,
        interval: TimeInterval
    ) async -> Bool {
        var schedule = schedules[account.id] ?? Schedule()
        schedule.failures += 1
        if case .rateLimited(let until) = error {
            let clamped = min(until, t + Self.maxRateLimitWait)
            schedule.rateLimitedUntil = clamped
            schedule.nextDue = clamped
        } else {
            schedule.rateLimitedUntil = nil
            schedule.nextDue = t + Backoff.delay(baseInterval: interval, consecutiveFailures: schedule.failures)
        }
        schedules[account.id] = schedule

        var wasUnauthorized = false
        if case .failed(let previous, let since) = statuses[account.id], previous == error {
            wasUnauthorized = previous == .unauthorized
            statuses[account.id] = .failed(error, since: since)
        } else {
            statuses[account.id] = .failed(error, since: t)
        }
        logger.warning("poll mislukt voor \(account.displayName): \(error.userMessage)")

        guard error == .unauthorized else { return false }
        userIds[account.id] = nil
        await provider.invalidateCredentials()
        return !wasUnauthorized
    }
}
