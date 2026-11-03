import AppKit
import os
import PullwatchCore
import UserNotifications

/// Log is Sendable; ook bruikbaar vanuit nonisolated callbacks.
nonisolated private let logger = Log(category: "notifier")

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// Wordt aangeroepen met de dedupKey wanneer de gebruiker op een PR-melding klikt.
    var onOpen: ((String) -> Void)?
    /// Klik op een melding die bij een onderdeel van het hoofdvenster hoort (bv. nieuwe versies).
    var onOpenSection: ((String) -> Void)?

    private var center: UNUserNotificationCenter { .current() }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("notificatie-toestemming mislukt: \(error.localizedDescription)")
            return false
        }
    }

    func isAuthorized() async -> Bool {
        await Self.authorizationGranted()
    }

    /// Of macOS al gevraagd heeft, en wat het antwoord was.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Opent de meldingsinstellingen van Pullwatch in Systeeminstellingen.
    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? "nl.torrisi.pullwatch"
        let app = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")!
        let all = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        if !NSWorkspace.shared.open(app) { NSWorkspace.shared.open(all) }
    }

    private nonisolated static func authorizationGranted() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    /// De tekst van een melding: de PR of tag, met daaronder wie hem maakte.
    private static func body(_ title: String, author: String?) -> String {
        guard let author, !author.isEmpty else { return title }
        return title + "\n" + String(localized: "door \(author)", comment: "Wie de PR of tag maakte")
    }

    func deliver(_ plans: [PlannedNotification]) {
        for plan in plans {
            let content = UNMutableNotificationContent()
            let identifier: String
            switch plan {
            case .pullRequest(let pr):
                content.title = String(localized: "\(pr.repo): nieuwe PR", comment: "Meldingstitel; repo")
                content.body = Self.body(pr.title, author: pr.authorName)
                content.userInfo = ["url": pr.webURL.absoluteString, "key": pr.dedupKey]
                identifier = pr.dedupKey
            case .tag(let tag):
                // Een release (ook van een tag die er al was) heet naar zijn titel.
                switch tag.release?.isPrerelease {
                case true?:
                    content.title = String(localized: "\(tag.repo): nieuwe pre-release", comment: "Meldingstitel; repo")
                case false?:
                    content.title = String(localized: "\(tag.repo): nieuwe release", comment: "Meldingstitel; repo")
                case nil:
                    content.title = String(localized: "\(tag.repo): nieuwe tag", comment: "Meldingstitel; repo")
                }
                content.body = Self.body(tag.releaseTitle ?? tag.name, author: tag.authorName)
                content.userInfo = ["url": tag.webURL.absoluteString, "key": tag.dedupKey]
                identifier = tag.dedupKey
            case .completed(let pr):
                content.title = String(localized: "\(pr.repo): PR completed", comment: "Meldingstitel; repo. Completed is de Azure DevOps-term voor gemerged")
                content.body = Self.body(pr.title, author: pr.authorName)
                content.userInfo = ["url": pr.webURL.absoluteString, "key": pr.dedupKey]
                identifier = pr.dedupKey + ":completed"
            case .summary(let kind, let count, let lines):
                switch kind {
                case .pullRequest: content.title = String(localized: "\(count) nieuwe PR's", comment: "Meldingstitel; aantal")
                case .tag: content.title = String(localized: "\(count) nieuwe tags", comment: "Meldingstitel; aantal")
                case .release: content.title = String(localized: "\(count) nieuwe releases", comment: "Meldingstitel; aantal")
                case .completed: content.title = String(localized: "\(count) PR's completed", comment: "Meldingstitel; aantal gemergde PR's")
                }
                content.body = lines.joined(separator: "\n")
                identifier = UUID().uuidString
            }
            content.sound = .default
            add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        }
    }

    /// Tot drie losse meldingen (klik opent de pagina van GitHubs advies, anders die van OSV),
    /// daarboven één samenvatting. Elke melding noemt CVE en GHSA-id, GitHubs ernst met de
    /// CVSS-score, en of het lek direct of via een ander package binnenkomt.
    func deliverVulnerabilities(_ items: [(repo: String, vulnerability: Vulnerability)], report: VersionReport) {
        func line(_ v: Vulnerability) -> String {
            let advisory = report.advisory(for: v)
            let severity = v.severityText(advisory).map { " [\($0)]" } ?? ""
            let fix = v.fixedIn.map { " → \($0)" } ?? ""
            return "\(v.identifiers(advisory))\(severity) \(v.package) \(v.version)\(fix)"
        }
        if items.count <= 3 {
            for (repo, v) in items {
                let advisory = report.advisory(for: v)
                let content = UNMutableNotificationContent()
                content.title = String(localized: "\(repo): nieuwe kwetsbaarheid", comment: "Meldingstitel; repo")
                // Direct of via welk package, en waar: dan weet je meteen wat je moet bijwerken.
                content.body = [line(v), v.provenanceLine, advisory?.cweText, advisory?.summary ?? v.summary]
                    .compactMap { $0 }.joined(separator: "\n")
                content.userInfo = ["url": (advisory?.url ?? v.url).absoluteString]
                content.sound = .default
                add(UNNotificationRequest(identifier: "cve-\(repo)-\(v.id)-\(v.package)", content: content, trigger: nil))
            }
        } else {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(items.count) nieuwe kwetsbaarheden", comment: "Meldingstitel; aantal")
            let lines = items.prefix(3).map { item in
                "\(item.repo): \(line(item.vulnerability))" + (item.vulnerability.provenanceLine.map { " (\($0))" } ?? "")
            }
            content.body = (lines + [String(localized: "Zie Afhankelijkheden in het hoofdvenster")]).joined(separator: "\n")
            content.sound = .default
            add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    /// Nieuwe critical- en high-meldingen van code scanning of Advanced Security: tot drie losse
    /// meldingen (klik opent de melding bij de dienst), daarboven één samenvatting.
    func deliverSecurityAlerts(_ items: [(repo: String, alert: SecurityAlert)]) {
        func line(_ alert: SecurityAlert) -> String {
            "[\(String(localized: alert.severityLabel))] \(alert.title)"
        }
        if items.count <= 3 {
            for (repo, alert) in items {
                let content = UNMutableNotificationContent()
                content.title = String(localized: "\(repo): nieuwe beveiligingsmelding", comment: "Meldingstitel; repo")
                content.body = [line(alert), alert.locationText, alert.ruleText].compactMap { $0 }.joined(separator: "\n")
                content.userInfo = ["url": alert.url.absoluteString]
                content.sound = .default
                add(UNNotificationRequest(identifier: "alert-\(repo)-\(alert.id)", content: content, trigger: nil))
            }
        } else {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(items.count) nieuwe beveiligingsmeldingen", comment: "Meldingstitel; aantal")
            let lines = items.prefix(3).map { "\($0.repo): \(line($0.alert))" }
            content.body = (lines + [String(localized: "+ \(items.count - 3) meer", comment: "Laatste regel van een melding; aantal regels dat niet getoond wordt")])
                .joined(separator: "\n")
            content.sound = .default
            add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    /// Eén melding voor alle nieuwe versies van één check; klik opent het onderdeel Versies.
    func deliverPackageUpdates(_ items: [PackageSummary]) {
        guard !items.isEmpty else { return }
        let lines = items.map { "\($0.label) \($0.latest ?? "")" }
        let content = UNMutableNotificationContent()
        if let only = items.first, items.count == 1 {
            content.title = String(localized: "\(only.label) \(only.latest ?? "") beschikbaar", comment: "Package, versie")
            content.body = String(localized: "\(only.behind.count) repo's lopen achter", comment: "Meldingstekst; aantal repo's met een oudere versie")
        } else {
            content.title = String(localized: "\(items.count) nieuwe versies", comment: "Meldingstitel; aantal packages met een nieuwe versie")
            content.body = (lines.prefix(3) + (items.count > 3 ? [String(localized: "+ \(items.count - 3) meer", comment: "Laatste regel van een melding; aantal regels dat niet getoond wordt")] : []))
                .joined(separator: "\n")
        }
        content.userInfo = ["section": "versions"]
        content.sound = .default
        add(UNNotificationRequest(identifier: "packages-\(lines.joined(separator: ","))", content: content, trigger: nil))
    }

    /// Klik opent de DMG (of de releasepagina als die er niet bij staat).
    func deliverUpdate(_ update: AvailableUpdate) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Pullwatch \(update.version) is beschikbaar", comment: "Meldingstitel; versienummer")
        content.body = String(localized: "Klik om te downloaden.")
        content.userInfo = ["url": (update.downloadURL ?? update.pageURL).absoluteString]
        add(UNNotificationRequest(identifier: "update-\(update.version)", content: content, trigger: nil))
    }

    func deliverAuthFailure(accountName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Pullwatch: \(accountName)"
        content.body = String(localized: "Token ongeldig of verlopen. Werk het bij in Instellingen.")
        add(UNNotificationRequest(identifier: "auth-\(accountName)", content: content, trigger: nil))
    }

    private func add(_ request: UNNotificationRequest) {
        center.add(request) { error in
            if let error {
                logger.error("melding toevoegen mislukt: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let urlString = info["url"] as? String
        let key = info["key"] as? String
        let section = info["section"] as? String
        await MainActor.run {
            if let section {
                self.onOpenSection?(section)
            }
            if let urlString, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
            if let key {
                self.onOpen?(key)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
