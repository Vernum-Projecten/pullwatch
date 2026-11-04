import Foundation
import PullwatchCore

/// Maakt van wat de planner en de versiecheck melden de tekst, groep, knoppen en het belang van
/// elke melding (Apple HIG "Notifications"): de titel zegt wat er gebeurde, de ondertitel de
/// repository (bij een PR met zijn nummer, `FerroHEALTH/FerroFED #1570`), de tekst de PR of release met wie hem maakte. Geen tekst aan elkaar geplakt met
/// dubbelepunten; elke zin is één string in de catalog. Puur: geen UserNotifications, geen
/// netwerk, dus volledig te testen (`NotificationContentTests`).
///
/// `summaryArgument` en `summaryArgumentCount` zet Pullwatch niet: Apple negeert ze sinds macOS 12
/// en iOS 15 ("summaryArgument is ignored" in de SDK), en `categorySummaryFormat` bestaat op macOS
/// niet. macOS stapelt per `threadIdentifier` en telt zelf.
struct NotificationContentBuilder {
    /// Voor de soort dienst (GitHub, GitLab) en de profielfoto's.
    var accounts: [Account] = []
    /// In de stille uren: alles zonder geluid en alleen in het Berichtencentrum.
    var quiet = false
    /// De taal van de teksten; tests kiezen er een.
    var bundle: Bundle = .main

    // MARK: - PR's, releases en tags

    func content(for plan: PlannedNotification<RepositoryItem>) -> NotificationContent {
        switch plan {
        case .single(let item): content(for: item)
        case .summary(let key, let items): summary(key, items)
        }
    }

    func content(for item: RepositoryItem) -> NotificationContent {
        let key = item.repository
        let account = account(key.accountId)
        let title: String
        let body: [String?]
        let url: URL
        var avatar: URL?
        // Bij een PR het nummer achter de repo, met het teken van de dienst van het account.
        let subtitle = switch item {
        case .pullRequest(let pr), .merged(let pr), .checksFailed(let pr): account.map { pr.repoAndNumber($0.kind) } ?? key.repo
        case .tag: key.repo
        }
        switch item {
        case .pullRequest(let pr):
            title = newPullRequestTitle(pr, account: account)
            body = [pr.title, byline(pr.authorName, others: pr.coAuthors.map(\.handle))]
            url = pr.webURL
            avatar = authorAvatar(pr, account: account)
        case .merged(let pr):
            title = mergedTitle(account)
            body = [pr.title, byline(pr.authorName, others: pr.coAuthors.map(\.handle))]
            url = pr.webURL
            avatar = authorAvatar(pr, account: account)
        case .checksFailed(let pr):
            title = String(localized: "Checks mislukt", bundle: bundle, comment: "Meldingstitel; de checks (CI) van een eigen PR mislukten")
            body = [pr.title, pr.checks?.counts.map(failedLine)]
            url = pr.webURL
        case .tag(let tag):
            title = tagTitle(tag)
            body = [tag.releaseTitle, byline(tag.release?.authorLogin ?? tag.authorName, others: [])]
            url = tag.webURL
            avatar = tag.release?.authorAvatarURL ?? tag.authorAvatarURL
        }
        return NotificationContent(
            identifier: item.notificationIdentifier,
            kind: item.kind,
            title: title,
            subtitle: subtitle,
            body: lines(body),
            threadIdentifier: key.threadIdentifier,
            category: .item,
            importance: .of(item.kind, quiet: quiet),
            avatarURL: avatar,
            payload: NotificationPayload(
                url: url, historyKeys: [item.historyKey], accountId: key.accountId, repo: key.repo,
                watchKinds: [item.watchKind]
            )
        )
    }

    /// Boven de grens per poll: één melding per repository met hoeveel er is en de eerste drie.
    func summary(_ key: RepositoryKey, _ items: [RepositoryItem]) -> NotificationContent {
        let kinds = Set(items.map(\.kind))
        let count = items.count
        let account = account(key.accountId)
        let title: String = switch kinds.count == 1 ? kinds.first : nil {
        case .pullRequest?:
            account?.kind == .gitLab
                ? String(localized: "\(count) nieuwe merge requests", bundle: bundle, comment: "Meldingstitel; aantal nieuwe merge requests in één repo (GitLab)")
                : String(localized: "\(count) nieuwe pull requests", bundle: bundle, comment: "Meldingstitel; aantal nieuwe PR's in één repo")
        case .merged?:
            String(localized: "\(count) pull requests gemerged", bundle: bundle, comment: "Meldingstitel; aantal gemergde PR's in één repo")
        case .checksFailed?:
            String(localized: "Checks van \(count) pull requests mislukt", bundle: bundle, comment: "Meldingstitel; aantal eigen PR's in één repo waarvan de checks mislukten")
        case .release?:
            String(localized: "\(count) nieuwe releases", bundle: bundle, comment: "Meldingstitel; aantal nieuwe releases in één repo")
        case .tag?:
            String(localized: "\(count) nieuwe tags", bundle: bundle, comment: "Meldingstitel; aantal nieuwe tags in één repo")
        default:
            String(localized: "\(count) updates", bundle: bundle, comment: "Meldingstitel; aantal nieuwe PR's, releases en tags samen in één repo")
        }
        let names = items.map { item in
            switch item {
            case .pullRequest(let pr), .merged(let pr), .checksFailed(let pr): pr.title
            case .tag(let tag): tag.releaseTitle.map { "\(tag.name) \($0)" } ?? tag.name
            }
        }
        var watchKinds: [WatchKind] = []
        for kind in items.map(\.watchKind) where !watchKinds.contains(kind) { watchKinds.append(kind) }
        return NotificationContent(
            identifier: "summary:\(key.threadIdentifier):\(items.map(\.notificationIdentifier).joined(separator: ","))",
            kind: kinds.count == 1 ? kinds.first! : .pullRequest,
            title: title,
            subtitle: key.repo,
            body: firstLines(names),
            threadIdentifier: key.threadIdentifier,
            category: .summary,
            importance: NotificationImportance.strongest(items.map { .of($0.kind, quiet: quiet) }) ?? .of(.pullRequest, quiet: quiet),
            avatarURL: nil,
            payload: NotificationPayload(
                historyKeys: items.map(\.historyKey), accountId: key.accountId, repo: key.repo, watchKinds: watchKinds
            )
        )
    }

    // MARK: - Kwetsbaarheden en beveiligingsmeldingen

    func content(for plan: PlannedNotification<VulnerabilityNotice>) -> NotificationContent {
        switch plan {
        case .single(let notice): vulnerability(notice)
        case .summary(let key, let notices): vulnerabilities(key, notices)
        }
    }

    /// Eén kwetsbaarheid: de ernst in de titel, dan wat het lek is, welk package en waar het
    /// opgelost is, de id's met hun database en waar de ernst vandaan komt, hoe het in de repo
    /// komt en wat de oplossing vraagt. Een klik opent de pagina bij de database van het advies.
    func vulnerability(_ notice: VulnerabilityNotice) -> NotificationContent {
        let v = notice.vulnerability
        let advisory = notice.advisory
        let severity = (notice.severityLevel ?? advisory?.severity ?? v.severity)?.uppercased()
        let title = switch severity {
        case "CRITICAL": String(localized: "Kritieke kwetsbaarheid", bundle: bundle, comment: "Meldingstitel")
        case "HIGH": String(localized: "Ernstige kwetsbaarheid", bundle: bundle, comment: "Meldingstitel; ernst high")
        case "MODERATE", "MEDIUM": String(localized: "Matige kwetsbaarheid", bundle: bundle, comment: "Meldingstitel; ernst moderate")
        case "LOW": String(localized: "Lichte kwetsbaarheid", bundle: bundle, comment: "Meldingstitel; ernst low")
        default: String(localized: "Nieuwe kwetsbaarheid", bundle: bundle, comment: "Meldingstitel; ernst onbekend")
        }
        let package = v.fixedIn.map {
            String(localized: "\(v.package) \(v.version), opgelost in \($0)", bundle: bundle, comment: "Melding van een kwetsbaarheid; package, versie, versie met de oplossing")
        } ?? String(localized: "\(v.package) \(v.version), nog niet opgelost", bundle: bundle, comment: "Melding van een kwetsbaarheid; package, versie")
        let identifiers = notice.identifiers.isEmpty ? nil : notice.severityText.map { "\(notice.identifiers) [\($0)]" } ?? notice.identifiers
        let rank = switch severity {
        case "CRITICAL": 4
        case "HIGH": 3
        case "MODERATE", "MEDIUM": 2
        case "LOW": 1
        default: 0
        }
        return NotificationContent(
            identifier: "cve-\(notice.repository.threadIdentifier)-\(v.id)-\(v.package)",
            kind: .vulnerability,
            title: title,
            subtitle: notice.repo,
            body: lines([advisory?.summary ?? v.summary, package, identifiers, notice.severityNote, notice.provenance, notice.fixText]),
            threadIdentifier: notice.repository.threadIdentifier,
            category: .vulnerability,
            importance: .of(.vulnerability, severityRank: rank, quiet: quiet),
            avatarURL: nil,
            payload: NotificationPayload(
                url: v.pageURL, accountId: notice.accountId, repo: notice.repo, package: v.package,
                advisoryId: v.id
            )
        )
    }

    func vulnerabilities(_ key: RepositoryKey, _ notices: [VulnerabilityNotice]) -> NotificationContent {
        let count = notices.count
        let worst = notices.map(\.vulnerability.severityRank).max() ?? 0
        return NotificationContent(
            identifier: "cve-\(key.threadIdentifier)-\(notices.map(\.vulnerability.id).joined(separator: ","))",
            kind: .vulnerability,
            title: String(localized: "\(count) nieuwe kwetsbaarheden", bundle: bundle, comment: "Meldingstitel; aantal nieuwe kwetsbaarheden in één repo"),
            subtitle: key.repo,
            body: firstLines(notices.map { "\($0.vulnerability.package) \($0.vulnerability.version)" }),
            threadIdentifier: key.threadIdentifier,
            category: .finding,
            importance: .of(.vulnerability, severityRank: worst, quiet: quiet),
            avatarURL: nil,
            payload: NotificationPayload(accountId: key.accountId, repo: key.repo)
        )
    }

    func content(for plan: PlannedNotification<SecurityAlertNotice>) -> NotificationContent {
        switch plan {
        case .single(let notice): securityAlert(notice)
        case .summary(let key, let notices): securityAlerts(key, notices)
        }
    }

    func securityAlert(_ notice: SecurityAlertNotice) -> NotificationContent {
        let alert = notice.alert
        let title = switch alert.severity {
        case "CRITICAL": String(localized: "Kritieke beveiligingsmelding", bundle: bundle, comment: "Meldingstitel; code scanning of Advanced Security")
        case "HIGH": String(localized: "Ernstige beveiligingsmelding", bundle: bundle, comment: "Meldingstitel; code scanning of Advanced Security, ernst high")
        default: String(localized: "Nieuwe beveiligingsmelding", bundle: bundle, comment: "Meldingstitel; code scanning of Advanced Security")
        }
        let location = alert.path.map { path in alert.line.map { "\(path):\($0)" } ?? path }
        let rule = [alert.rule, alert.tool.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
        return NotificationContent(
            identifier: "alert-\(notice.repository.threadIdentifier)-\(alert.id)",
            kind: .securityAlert,
            title: title,
            subtitle: notice.repo,
            body: lines([alert.title, location, rule.isEmpty ? nil : rule]),
            threadIdentifier: notice.repository.threadIdentifier,
            category: .finding,
            importance: .of(.securityAlert, severityRank: alert.severityRank, quiet: quiet),
            avatarURL: nil,
            payload: NotificationPayload(url: alert.url, accountId: notice.accountId, repo: notice.repo)
        )
    }

    func securityAlerts(_ key: RepositoryKey, _ notices: [SecurityAlertNotice]) -> NotificationContent {
        let count = notices.count
        return NotificationContent(
            identifier: "alert-\(key.threadIdentifier)-\(notices.map(\.alert.id).joined(separator: ","))",
            kind: .securityAlert,
            title: String(localized: "\(count) nieuwe beveiligingsmeldingen", bundle: bundle, comment: "Meldingstitel; aantal in één repo"),
            subtitle: key.repo,
            body: firstLines(notices.map(\.alert.title)),
            threadIdentifier: key.threadIdentifier,
            category: .finding,
            importance: .of(.securityAlert, severityRank: notices.map(\.alert.severityRank).max() ?? 0, quiet: quiet),
            avatarURL: nil,
            payload: NotificationPayload(accountId: key.accountId, repo: key.repo)
        )
    }

    // MARK: - Nieuwe versies, de update van Pullwatch, een account

    /// Eén melding voor alle nieuwe versies van één check; een klik opent Afhankelijkheden.
    func packageUpdates(_ items: [PackageSummary]) -> NotificationContent? {
        guard let first = items.first else { return nil }
        let title: String
        let subtitle: String
        let body: String
        if items.count == 1 {
            let latest = first.latest ?? ""
            title = String(localized: "\(first.label) \(latest) beschikbaar", bundle: bundle, comment: "Meldingstitel; package, versie")
            subtitle = String(localized: "\(first.behind.count) repo's lopen achter", bundle: bundle, comment: "Ondertitel van een melding; aantal repo's met een oudere versie")
            body = first.canUpdateNowCount > 0
                ? String(localized: "In \(first.canUpdateNowCount) repo's binnen het bereik bij te werken", bundle: bundle, comment: "Meldingstekst; aantal repo's dat de nieuwe versie nu kan nemen")
                : String(localized: first.category.title)
        } else {
            title = String(localized: "\(items.count) nieuwe versies", bundle: bundle, comment: "Meldingstitel; aantal packages met een nieuwe versie")
            subtitle = String(localized: "Afhankelijkheden", bundle: bundle, comment: "Ondertitel van een melding van nieuwe versies; het onderdeel van het hoofdvenster")
            body = firstLines(items.map { "\($0.label) \($0.latest ?? "")" })
        }
        let importance = NotificationImportance.of(.packageUpdate, quiet: quiet)
        return NotificationContent(
            identifier: "packages-\(items.map { "\($0.label) \($0.latest ?? "")" }.joined(separator: ","))",
            kind: .packageUpdate,
            title: title,
            subtitle: subtitle,
            body: body,
            threadIdentifier: "versions",
            category: nil,
            importance: importance,
            avatarURL: nil,
            payload: NotificationPayload(section: "versions", package: items.count == 1 ? first.label : nil)
        )
    }

    /// Een klik opent Sparkle's venster om te installeren, of zonder Sparkle de DMG (of de
    /// releasepagina als die er niet bij staat).
    func appUpdate(_ update: AvailableUpdate) -> NotificationContent {
        NotificationContent(
            identifier: "update-\(update.version)",
            kind: .appUpdate,
            title: String(localized: "Pullwatch \(update.version) is beschikbaar", bundle: bundle, comment: "Meldingstitel; versienummer"),
            subtitle: "",
            body: update.installsInApp
                ? String(localized: "Klik om te installeren.", bundle: bundle)
                : String(localized: "Klik om te downloaden.", bundle: bundle),
            threadIdentifier: "update",
            category: nil,
            importance: .of(.appUpdate, quiet: quiet),
            avatarURL: nil,
            payload: update.installsInApp
                ? NotificationPayload(installsUpdate: true)
                : NotificationPayload(url: update.downloadURL ?? update.pageURL)
        )
    }

    func authFailure(_ account: Account) -> NotificationContent {
        NotificationContent(
            identifier: "auth-\(account.id.uuidString)",
            kind: .account,
            title: account.displayName,
            subtitle: "",
            body: String(localized: "Token ongeldig of verlopen. Werk het bij in Instellingen.", bundle: bundle),
            threadIdentifier: "account-\(account.id.uuidString)",
            category: nil,
            importance: .of(.account, quiet: quiet),
            avatarURL: nil,
            payload: NotificationPayload(section: "settings")
        )
    }

    /// Een agent die zich voor het eerst meldt: Toestaan of Niet toestaan. `clientName` is
    /// `clientInfo.name` (waar toestaan op gaat), `displayName` de naam die de persoon kent.
    func agentApproval(clientName: String, displayName: String) -> NotificationContent {
        NotificationContent(
            identifier: Self.agentApprovalIdentifier(clientName),
            kind: .agent,
            title: String(localized: "\(displayName) wil Pullwatch gebruiken", bundle: bundle, comment: "Meldingstitel; naam van een coding agent, zoals Claude Code"),
            subtitle: "",
            body: String(
                localized: "De agent leest dan je pull requests, repo's en kwetsbaarheden in Pullwatch. Wat hij leest, gaat naar zijn modelaanbieder.",
                bundle: bundle, comment: "Melding als een coding agent voor het eerst Pullwatch wil gebruiken"
            ),
            threadIdentifier: "agents",
            category: .agent,
            importance: .of(.agent, quiet: quiet),
            avatarURL: nil,
            payload: NotificationPayload(section: "settings", agentName: clientName)
        )
    }

    /// De id van de vraag om `clientName`, om hem na het antwoord weg te halen.
    static func agentApprovalIdentifier(_ clientName: String) -> String {
        "agent-\(clientName)"
    }

    // MARK: - Stukjes tekst

    private func account(_ id: UUID?) -> Account? {
        id.flatMap { id in accounts.first { $0.id == id } }
    }

    private func newPullRequestTitle(_ pr: PullRequest, account: Account?) -> String {
        switch (account?.kind == .gitLab, pr.isDraft) {
        case (true, true): String(localized: "Nieuwe concept-merge request", bundle: bundle, comment: "Meldingstitel; GitLab")
        case (true, false): String(localized: "Nieuwe merge request", bundle: bundle, comment: "Meldingstitel; GitLab")
        case (false, true): String(localized: "Nieuwe concept-pull request", bundle: bundle, comment: "Meldingstitel; een PR die nog concept (draft) is")
        case (false, false): String(localized: "Nieuwe pull request", bundle: bundle, comment: "Meldingstitel")
        }
    }

    /// "1 van 8 checks mislukt", onder de titel van de PR.
    private func failedLine(_ counts: CheckCounts) -> String {
        String(localized: "\(counts.failed) van \(counts.total) checks mislukt", bundle: bundle, comment: "Melding; aantal mislukte checks, totaal")
    }

    private func mergedTitle(_ account: Account?) -> String {
        switch account?.kind {
        case .gitLab?: String(localized: "Merge request gemerged", bundle: bundle, comment: "Meldingstitel; GitLab")
        case .azureDevOps?: String(localized: "Pull request afgerond", bundle: bundle, comment: "Meldingstitel; Azure DevOps noemt mergen completed")
        default: String(localized: "Pull request gemerged", bundle: bundle, comment: "Meldingstitel")
        }
    }

    /// Een release heet naar zijn tag ("Nieuwe release v1.2.0"); zijn titel staat in de tekst.
    private func tagTitle(_ tag: Tag) -> String {
        switch tag.release?.isPrerelease {
        case true?: String(localized: "Nieuwe pre-release \(tag.name)", bundle: bundle, comment: "Meldingstitel; tagnaam")
        case false?: String(localized: "Nieuwe release \(tag.name)", bundle: bundle, comment: "Meldingstitel; tagnaam")
        case nil: String(localized: "Nieuwe tag \(tag.name)", bundle: bundle, comment: "Meldingstitel; tagnaam")
        }
    }

    /// "door mona", "door mona en hubot", "door mona en 2 anderen".
    func byline(_ author: String?, others: [String]) -> String? {
        guard let author = author?.trimmingCharacters(in: .whitespaces), !author.isEmpty else { return nil }
        let others = others.filter { $0.caseInsensitiveCompare(author) != .orderedSame }
        switch others.count {
        case 0:
            return String(localized: "door \(author)", bundle: bundle, comment: "Wie de PR of tag maakte")
        case 1:
            return String(localized: "door \(author) en \(others[0])", bundle: bundle, comment: "Wie de PR maakte en de enige co-auteur")
        default:
            let count = others.count
            return String(localized: "door \(author) en \(count) anderen", bundle: bundle, comment: "Wie de PR maakte; aantal co-auteurs")
        }
    }

    /// De eerste drie regels, en daaronder hoeveel er nog zijn.
    private func firstLines(_ all: [String]) -> String {
        var shown = Array(all.prefix(3))
        if all.count > 3 {
            let more = all.count - 3
            shown.append(String(localized: "en nog \(more)", bundle: bundle, comment: "Laatste regel van een melding; aantal regels dat niet getoond wordt"))
        }
        return shown.joined(separator: "\n")
    }

    private func lines(_ parts: [String?]) -> String {
        parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// De foto die de provider gaf (ook van een bot), anders `/<login>.png` op github.com of de
    /// eigen GitHub Enterprise-server; voor een bot zonder foto van de API niets, want die route
    /// kent geen GitHub App. Azure DevOps geeft geen foto zonder inloggen.
    private func authorAvatar(_ pr: PullRequest, account: Account?) -> URL? {
        guard let account else { return pr.authorAvatarURL }
        return Account.authorAvatarURL(pr.authorAvatarURL, login: pr.authorName, kind: account.kind, size: 64, web: account.effectiveInstanceURL)
    }
}
