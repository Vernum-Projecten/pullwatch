import Foundation
import os

private let logger = Log(category: "engine")

/// Pushes naar branches: ophalen bij de provider (`fetchBranches`) en verwerken tegen de
/// onthouden heads (`handleBranches`).
extension PollEngine {
    /// Waar een poll de branches van ophaalt: het account (eigen instellingen, standaard) en de
    /// onthouden heads per repo, met sleutels zonder accountprefix, lowercased.
    struct BranchRepos: Sendable {
        let account: Account
        let known: [String: BranchHeads]
    }

    /// Uitkomst van het ophalen van branches in één poll.
    struct BranchOutcome: Sendable {
        /// De repo's waarvan de branches gevolgd worden; bij branches als standaard uit de lijst
        /// van de dienst.
        var repos: [String]
        /// `nil` bij een fout.
        var fetch: BranchFetch?
        /// Vergelijkingen van veranderde heads, sleutel `branchKey(repo, branch)`.
        var comparisons: [String: BranchComparison]
        /// Fout die de branches van deze poll overslaat; het account faalt er nooit door.
        var error: ProviderError?
    }

    /// Sleutel van `BranchOutcome.comparisons`: `"{repo.lowercased()}:{branch}"`.
    static func branchKey(_ repo: String, _ branch: String) -> String {
        "\(repo.lowercased()):\(branch)"
    }

    // MARK: - Ophalen

    /// Haalt de branches op van de gevolgde repo's, en bij branches als standaard van alle repo's
    /// in de lijst van de dienst (`listed` als de tag-fetch van deze poll die al ophaalde). Een
    /// bekende repo met een vingerafdruk wordt alleen helemaal opgehaald als die veranderde. Voor
    /// de veranderde heads (oud bekend, nieuw anders) volgt een vergelijking, hooguit
    /// `branchCompareLimit`, nieuwste commit eerst; een mislukte vergelijking valt weg en na een
    /// rate limit stopt het vergelijken. Gooit nooit: een fout komt in `BranchOutcome.error`.
    static func fetchBranches(
        _ provider: any PRProvider,
        _ repos: BranchRepos,
        listed: [String]? = nil
    ) async -> BranchOutcome {
        let account = repos.account
        var outcome = BranchOutcome(repos: account.branchRepos, fetch: nil, comparisons: [:], error: nil)
        do {
            if account.followsBranchesByDefault {
                let available: [String]
                if let listed {
                    available = listed
                } else {
                    available = try await provider.listRepos()
                }
                outcome.repos = account.branchRepos(available: available)
            }
            guard !outcome.repos.isEmpty else {
                outcome.fetch = BranchFetch()
                return outcome
            }
            var unchanged: [String: String] = [:]
            for repo in outcome.repos {
                if let fingerprint = repos.known[repo.lowercased()]?.fingerprint { unchanged[repo] = fingerprint }
            }
            let fetch = try await provider.branches(in: outcome.repos, unchanged: unchanged)
            outcome.fetch = fetch
            let skipped = Set((fetch.unchangedRepos + fetch.unavailableRepos).map { $0.lowercased() })
            let changed = fetch.heads
                .compactMap { head -> (head: BranchHead, old: String)? in
                    let key = head.repo.lowercased()
                    guard !skipped.contains(key), let old = repos.known[key]?.heads[head.name], old != head.sha
                    else { return nil }
                    return (head, old)
                }
                .sorted { a, b in
                    let (da, db) = (a.head.committedAt ?? .distantPast, b.head.committedAt ?? .distantPast)
                    return da != db ? da > db : (a.head.repo, a.head.name) < (b.head.repo, b.head.name)
                }
            for (head, old) in changed.prefix(branchCompareLimit) {
                do {
                    if let comparison = try await provider.compare(in: head.repo, from: old, to: head.sha) {
                        outcome.comparisons[branchKey(head.repo, head.name)] = comparison
                    }
                } catch ProviderError.rateLimited {
                    logger.notice("branches vergelijken gestopt door rate limit")
                    break
                } catch {
                    logger.notice("branch vergelijken mislukt voor \(head.repo): \(error.localizedDescription)")
                }
            }
            return outcome
        } catch let error as ProviderError {
            outcome.error = error
            return outcome
        } catch {
            outcome.error = .network(error.localizedDescription)
            return outcome
        }
    }

    // MARK: - Verwerken

    /// Maakt de rijen van deze branch-poll en werkt de onthouden heads bij. Een repo die nog niet
    /// bekend is seedt: elke branch die de afgelopen `branchSeedWindow` bewoog wordt een
    /// `.recent`-rij (een datum in de toekomst telt als nu), de rest wordt alleen onthouden. Een
    /// bekende repo geeft per veranderde head een `.push` of `.forcePush` en per nieuwe branch een
    /// `.newBranch`; een verdwenen branch geeft niets. Een onbereikbare repo houdt zijn heads en
    /// geeft niets; een repo die niet meer gevolgd wordt vergeet ze, zodat aanzetten opnieuw seedt.
    /// Bij een fout verandert er niets, en na een rate limit wachten de branches tot die voorbij is.
    func handleBranches(
        _ account: Account,
        _ outcome: BranchOutcome,
        userId: String,
        provider: any PRProvider,
        at t: Date
    ) -> [BranchPush] {
        if let error = outcome.error {
            var until: Date?
            if case .rateLimited(let date) = error { until = date }
            scheduleBranches(of: account, at: t, rateLimitedUntil: until)
            logger.warning("branches ophalen mislukt voor \(account.displayName): \(error.userMessage)")
            return []
        }
        scheduleBranches(of: account, at: t, rateLimitedUntil: nil)
        let wanted = Set(outcome.repos.map { $0.lowercased() })
        forgetBranchHeads(of: account, except: wanted)
        guard let fetch = outcome.fetch else { return [] }

        let prefix = "\(account.id.uuidString):"
        let unavailable = Set(fetch.unavailableRepos.map { $0.lowercased() })
        let unchanged = Set(fetch.unchangedRepos.map { $0.lowercased() })
        let fingerprints = Dictionary(
            fetch.fingerprints.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        let headsByRepo = Dictionary(grouping: fetch.heads) { $0.repo.lowercased() }
        if !unavailable.isEmpty {
            logger.warning("branches overgeslagen voor \(account.displayName): \(unavailable.sorted().joined(separator: ", ")) (niet gevonden of geen toegang)")
        }

        func row(_ head: BranchHead, old: String?, commits: Int?, kind: BranchPush.Kind, at date: Date) -> BranchPush {
            let compare = old.flatMap { provider.compareURL(in: head.repo, from: $0, to: head.sha) }
            return BranchPush(
                accountId: account.id, repo: head.repo, branch: head.name, oldSha: old, newSha: head.sha,
                commits: commits, kind: kind, authorName: head.authorName, authorAvatarURL: head.authorAvatarURL,
                isOwn: Self.isOwn(head, userId: userId, account: account), pushedAt: date,
                webURL: compare ?? head.webURL)
        }

        var pushes: [BranchPush] = []
        for repo in wanted.subtracting(unavailable) {
            let key = prefix + repo
            let known = state.branchHeads[key]
            if unchanged.contains(repo) {
                // Zonder onthouden heads is er niets om tegen te vergelijken; de volgende ronde seedt.
                state.branchHeads[key]?.seenAt = t
                continue
            }
            var heads: [String: String] = [:]
            for head in headsByRepo[repo] ?? [] where heads[head.name] == nil {
                heads[head.name] = head.sha
                if let known {
                    guard let old = known.heads[head.name] else {
                        pushes.append(row(head, old: nil, commits: nil, kind: .newBranch, at: t))
                        continue
                    }
                    guard old != head.sha else { continue }
                    let comparison = outcome.comparisons[Self.branchKey(head.repo, head.name)]
                    if let comparison, comparison.behind > 0 {
                        pushes.append(row(head, old: old, commits: nil, kind: .forcePush, at: t))
                    } else {
                        pushes.append(row(head, old: old, commits: comparison?.ahead, kind: .push, at: t))
                    }
                } else if let date = head.committedAt, date >= t - Self.branchSeedWindow {
                    pushes.append(row(head, old: nil, commits: nil, kind: .recent, at: min(date, t)))
                }
            }
            state.branchHeads[key] = BranchHeads(heads: heads, fingerprint: fingerprints[repo], seenAt: t)
        }
        return pushes
    }

    /// Vergeet de onthouden heads van de repo's (lowercased) van dit account die niet in `kept` staan.
    func forgetBranchHeads(of account: Account, except kept: Set<String>) {
        let prefix = "\(account.id.uuidString):"
        state.branchHeads = state.branchHeads.filter { key, _ in
            !key.hasPrefix(prefix) || kept.contains(String(key.dropFirst(prefix.count)))
        }
    }

    /// Is deze branch-head van de gebruiker zelf: op account-id (`userId`), anders op het
    /// e-mailadres of de login van het account. Alles hoofdletterongevoelig.
    static func isOwn(_ head: BranchHead, userId: String, account: Account) -> Bool {
        func same(_ a: String?, _ b: String?) -> Bool {
            guard let a, let b, !a.isEmpty else { return false }
            return a.caseInsensitiveCompare(b) == .orderedSame
        }
        return same(head.authorId, userId)
            || same(head.authorEmail, account.email)
            || same(head.authorId, account.login)
            || same(head.authorName, account.login)
    }
}
