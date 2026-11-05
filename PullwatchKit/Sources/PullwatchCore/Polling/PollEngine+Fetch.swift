import Foundation
import os

private let logger = Log(category: "engine")

// MARK: - Ophalen bij de provider

extension PollEngine {
    static func fetch(
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
            let unreadMergeQueues = await provider.unreadMergeQueues()
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
                unreadMergeQueues: unreadMergeQueues,
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

    static func isOwn(_ pr: PullRequest, userId: String) -> Bool {
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
}
