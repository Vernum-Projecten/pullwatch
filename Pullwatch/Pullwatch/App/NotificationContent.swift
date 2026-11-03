import Foundation
import PullwatchCore

/// Een melding zoals hij op het scherm komt, los van UserNotifications: wat de
/// `NotificationContentBuilder` maakt en de `Notifier` aflevert. Zo is alles wat de melding zegt
/// en doet te testen zonder er een te versturen.
nonisolated struct NotificationContent: Equatable, Sendable {
    /// `UNNotificationRequest.identifier`: vast per item, zodat een nieuwe melding voor hetzelfde
    /// de oude vervangt en "gelezen" in Pullwatch hem weg kan halen.
    var identifier: String
    var kind: NotificationKind
    /// Wat er gebeurde, in een paar woorden ("Nieuwe pull request").
    var title: String
    /// De repository, of bij nieuwe versies hoeveel repo's achterlopen.
    var subtitle: String
    /// De titel van de PR of release, met wie hem maakte; bij een kwetsbaarheid wat en waar.
    var body: String
    /// macOS stapelt meldingen met dezelfde waarde; per account en repository.
    var threadIdentifier: String
    var category: NotificationCategory?
    var importance: NotificationImportance
    /// Profielfoto van de auteur, als die er is; anders krijgt de melding het teken van de soort.
    var avatarURL: URL?
    var payload: NotificationPayload
}

/// Wat een klik of knop op de melding nodig heeft, in `userInfo` (alleen tekst en lijsten van
/// tekst, zoals UserNotifications vraagt).
nonisolated struct NotificationPayload: Equatable, Sendable {
    /// Wat een klik op de melding zelf opent.
    var url: URL?
    /// `HistoryItem.id`'s die deze melding noemt: een klik of "Markeer als gelezen" leest ze, en
    /// als ze in Pullwatch gelezen zijn gaat de melding weg.
    var historyKeys: [String] = []
    /// `MainSection.rawValue` dat een klik opent.
    var section: String?
    /// Een klik installeert de update.
    var installsUpdate = false
    var accountId: UUID?
    var repo: String?
    /// Wat "Repo dempen" uitzet.
    var watchKinds: [WatchKind] = []
    /// Waar "Toon in Pullwatch" op zoekt.
    var package: String?
    /// Wat "Advies-id kopiëren" op het klembord zet.
    var advisoryId: String?

    private enum Key {
        static let url = "url", key = "key", keys = "keys", section = "section", action = "action"
        static let accountId = "accountId", repo = "repo", watchKinds = "watchKinds", package = "package", advisoryId = "advisoryId"
    }

    var userInfo: [String: any Sendable] {
        var info: [String: any Sendable] = [:]
        if let url { info[Key.url] = url.absoluteString }
        if !historyKeys.isEmpty {
            info[Key.keys] = historyKeys
            // Een oudere Pullwatch las alleen `key`.
            if historyKeys.count == 1 { info[Key.key] = historyKeys[0] }
        }
        if let section { info[Key.section] = section }
        if installsUpdate { info[Key.action] = "install-update" }
        if let accountId { info[Key.accountId] = accountId.uuidString }
        if let repo { info[Key.repo] = repo }
        if !watchKinds.isEmpty { info[Key.watchKinds] = watchKinds.map(\.rawValue) }
        if let package { info[Key.package] = package }
        if let advisoryId { info[Key.advisoryId] = advisoryId }
        return info
    }

    init(
        url: URL? = nil, historyKeys: [String] = [], section: String? = nil, installsUpdate: Bool = false,
        accountId: UUID? = nil, repo: String? = nil, watchKinds: [WatchKind] = [], package: String? = nil,
        advisoryId: String? = nil
    ) {
        self.url = url
        self.historyKeys = historyKeys
        self.section = section
        self.installsUpdate = installsUpdate
        self.accountId = accountId
        self.repo = repo
        self.watchKinds = watchKinds
        self.package = package
        self.advisoryId = advisoryId
    }

    /// Leest `userInfo` terug, ook van een melding die een oudere Pullwatch verstuurde.
    init(userInfo: [AnyHashable: Any]) {
        url = (userInfo[Key.url] as? String).flatMap(URL.init(string:))
        historyKeys = userInfo[Key.keys] as? [String] ?? (userInfo[Key.key] as? String).map { [$0] } ?? []
        section = userInfo[Key.section] as? String
        installsUpdate = userInfo[Key.action] as? String == "install-update"
        accountId = (userInfo[Key.accountId] as? String).flatMap(UUID.init(uuidString:))
        repo = userInfo[Key.repo] as? String
        watchKinds = (userInfo[Key.watchKinds] as? [String] ?? []).compactMap(WatchKind.init(rawValue:))
        package = userInfo[Key.package] as? String
        advisoryId = userInfo[Key.advisoryId] as? String
    }
}

/// `UNNotificationCategory`: welke knoppen een melding heeft.
nonisolated enum NotificationCategory: String, CaseIterable, Sendable {
    /// Een PR, gemergde PR, release of tag.
    case item
    /// Meerdere items van één repository (boven de grens per poll).
    case summary
    /// Eén kwetsbaarheid.
    case vulnerability
    /// Een beveiligingsmelding, of meerdere kwetsbaarheden van één repository.
    case finding

    var identifier: String { "nl.torrisi.pullwatch.\(rawValue)" }

    init?(identifier: String) {
        guard let match = Self.allCases.first(where: { $0.identifier == identifier }) else { return nil }
        self = match
    }

    /// Hooguit vier, zoals de HIG vraagt; openen is de klik op de melding zelf, geen knop.
    var actions: [NotificationAction] {
        switch self {
        case .item: [.markRead, .openRepository, .mute]
        case .summary: [.markAllRead, .openRepository, .mute]
        case .vulnerability: [.showInPullwatch, .copyAdvisoryId, .openRepository]
        case .finding: [.openRepository]
        }
    }
}

/// Een knop op een melding.
nonisolated enum NotificationAction: String, CaseIterable, Sendable {
    case markRead, markAllRead, openRepository, mute, showInPullwatch, copyAdvisoryId

    var identifier: String { "nl.torrisi.pullwatch.action.\(rawValue)" }

    init?(identifier: String) {
        guard let match = Self.allCases.first(where: { $0.identifier == identifier }) else { return nil }
        self = match
    }

    /// Een SF Symbol naast de titel van de knop.
    var symbol: String {
        switch self {
        case .markRead, .markAllRead: "checkmark.circle"
        case .openRepository: "folder"
        case .mute: "bell.slash"
        case .showInPullwatch: "shippingbox"
        case .copyAdvisoryId: "doc.on.doc"
        }
    }

    /// Opent een venster van Pullwatch; de andere knoppen doen hun werk zonder venster.
    var opensWindow: Bool { self == .openRepository || self == .showInPullwatch }

    var title: String {
        switch self {
        case .markRead: String(localized: "Markeer als gelezen", comment: "Knop op een melding")
        case .markAllRead: String(localized: "Alles als gelezen markeren", comment: "Knop op een melding van meerdere PR's of tags")
        case .openRepository: String(localized: "Repopagina openen", comment: "Knop op een melding: opent de pagina van de repo in Pullwatch")
        case .mute: String(localized: "Repo dempen", comment: "Knop op een melding: geen meldingen meer van deze soort voor deze repo")
        case .showInPullwatch: String(localized: "Toon in Pullwatch", comment: "Knop op een melding van een kwetsbaarheid: opent Afhankelijkheden")
        case .copyAdvisoryId: String(localized: "Advies-id kopiëren", comment: "Knop op een melding van een kwetsbaarheid: zet CVE of GHSA op het klembord")
        }
    }
}

/// Eén kwetsbaarheid in één repo, zoals de versiecheck hem nieuw vindt.
/// Wat de app er al over weet (GitHubs advies, de herkomst en de oplossing) staat erbij als
/// tekst, zodat de builder niets hoeft op te zoeken.
nonisolated struct VulnerabilityNotice: Equatable, Sendable {
    var accountId: UUID?
    var repo: String
    var vulnerability: Vulnerability
    var advisory: GitHubAdvisory? = nil
    /// "RUSTSEC-2026-0387 (RustSec), ook GHSA-… en CVE-…" (`Vulnerability.sourceLine`).
    var identifiers: String = ""
    /// "Kritiek, CVSS 9.1".
    var severityText: String? = nil
    /// De ernst uit de beste bron ("CRITICAL" … "LOW"; `Vulnerability.severityAssessment`).
    var severityLevel: String? = nil
    /// Waar die ernst vandaan komt ("Ernst uit CVSS 3.1 van RustSec").
    var severityNote: String? = nil
    /// Direct, of via welk package en waar.
    var provenance: String? = nil
    /// Wat de oplossing vraagt.
    var fixText: String? = nil

    var repository: RepositoryKey { RepositoryKey(accountId: accountId, repo: repo) }
}

/// Eén nieuwe critical- of high-melding van code scanning of Advanced Security in één repo.
nonisolated struct SecurityAlertNotice: Equatable, Sendable {
    var accountId: UUID?
    var repo: String
    var alert: SecurityAlert

    var repository: RepositoryKey { RepositoryKey(accountId: accountId, repo: repo) }
}

/// Wat "Repo dempen" uitzette, om het ongedaan te maken.
nonisolated struct RepositoryMute: Equatable, Sendable {
    var accountId: UUID
    var repo: String
    var kinds: [WatchKind]
    var previous: WatchSet
}
