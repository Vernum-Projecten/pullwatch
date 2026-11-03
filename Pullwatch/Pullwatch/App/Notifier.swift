import AppKit
import os
import PullwatchCore
import SwiftUI
import UserNotifications

/// Log is Sendable; ook bruikbaar vanuit nonisolated callbacks.
nonisolated private let logger = Log(category: "notifier")

/// Levert meldingen af die de `NotificationContentBuilder` maakte, met knoppen per categorie, een
/// profielfoto of het teken van de soort, en haalt ze weg als ze in Pullwatch gelezen zijn. Wat
/// er in een melding staat beslist deze klasse niet.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// Een klik op een melding of een knop erop; `nil` is de klik op de melding zelf.
    var onResponse: ((NotificationAction?, NotificationPayload) -> Void)?

    /// Profielfoto's voor de bijlagen, met de HTTP-client van de app.
    private lazy var avatars = AvatarCache(
        http: AppModel.networking,
        directory: URL.cachesDirectory.appending(path: "nl.torrisi.pullwatch/avatars")
    )

    private var center: UNUserNotificationCenter { .current() }

    /// Nooit een echte melding: als host van de unit-tests, en in debug-builds met
    /// `-PullwatchSkipNotificationRequest YES` (schermafbeeldingen en proefritten op een Mac waar
    /// iemand werkt). Dan vraagt Pullwatch ook geen toestemming.
    static var isSuppressed: Bool {
        if AppModel.isTestHost { return true }
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "PullwatchSkipNotificationRequest")
        #else
        return false
        #endif
    }

    /// De knoppen per soort melding; één keer bij het opstarten.
    func registerCategories() {
        let categories = NotificationCategory.allCases.map { category in
            UNNotificationCategory(
                identifier: category.identifier,
                actions: category.actions.map { action in
                    UNNotificationAction(
                        identifier: action.identifier,
                        title: action.title,
                        options: action.opensWindow ? [.foreground] : [],
                        icon: UNNotificationActionIcon(systemImageName: action.symbol)
                    )
                },
                intentIdentifiers: [],
                options: [.hiddenPreviewsShowSubtitle]
            )
        }
        center.setNotificationCategories(Set(categories))
    }

    func requestAuthorization() async -> Bool {
        if Self.isSuppressed { return false }
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("notificatie-toestemming mislukt: \(error.localizedDescription)")
            return false
        }
    }

    func isAuthorized() async -> Bool {
        if Self.isSuppressed { return false }
        return await Self.authorizationGranted()
    }

    /// Of macOS al gevraagd heeft, en wat het antwoord was.
    func authorizationStatus() async -> UNAuthorizationStatus {
        if Self.isSuppressed { return .notDetermined }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
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

    // MARK: - Afleveren

    func deliver(_ contents: [NotificationContent]) {
        guard !contents.isEmpty else { return }
        if Self.isSuppressed {
            logger.notice("\(contents.count) meldingen niet verstuurd (onderdrukt)")
            return
        }
        Task {
            for content in contents {
                await add(content)
            }
        }
    }

    private func add(_ content: NotificationContent) async {
        let request = UNMutableNotificationContent()
        request.title = content.title
        request.subtitle = content.subtitle
        request.body = content.body
        request.threadIdentifier = content.threadIdentifier
        request.categoryIdentifier = content.category?.identifier ?? ""
        request.interruptionLevel = content.importance.level == .active ? .active : .passive
        request.relevanceScore = content.importance.relevance
        request.sound = content.importance.playsSound ? .default : nil
        request.userInfo = content.payload.userInfo
        if let attachment = await attachment(for: content) {
            request.attachments = [attachment]
        }
        do {
            try await center.add(UNNotificationRequest(identifier: content.identifier, content: request, trigger: nil))
        } catch {
            logger.error("melding toevoegen mislukt: \(error.localizedDescription)")
        }
    }

    /// De profielfoto van de auteur, anders het teken van de soort. macOS verplaatst het bestand,
    /// dus elke melding krijgt een eigen kopie.
    private func attachment(for content: NotificationContent) async -> UNNotificationAttachment? {
        var file: URL?
        if let avatar = content.avatarURL {
            file = await avatars.attachmentFile(for: avatar)
        }
        if file == nil, let glyph = NotificationGlyph(kind: content.kind) {
            file = glyphFile(glyph)
        }
        guard let file else { return nil }
        do {
            return try UNNotificationAttachment(identifier: "picture", url: file)
        } catch {
            logger.error("bijlage onbruikbaar: \(error.localizedDescription)")
            return nil
        }
    }

    /// Het teken één keer als PNG getekend, dan per melding gekopieerd.
    private var glyphs: [NotificationGlyph: Data] = [:]

    private func glyphFile(_ glyph: NotificationGlyph) -> URL? {
        let data: Data
        if let cached = glyphs[glyph] {
            data = cached
        } else {
            let renderer = ImageRenderer(content: glyph.view)
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
            glyphs[glyph] = png
            data = png
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: "pullwatch-attachments/\(UUID().uuidString)")
        let file = folder.appending(path: "glyph.png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file)
            return file
        } catch {
            return nil
        }
    }

    // MARK: - Opruimen

    /// Haalt meldingen weg waarvan alle items gelezen zijn (`isRead`); meldingen zonder items
    /// (kwetsbaarheden, updates) blijven staan.
    func removeDelivered(whereRead isRead: @escaping (String) -> Bool) {
        if Self.isSuppressed { return }
        Task {
            let delivered = await center.deliveredNotifications()
            let identifiers = delivered.compactMap { notification -> String? in
                let keys = NotificationPayload(userInfo: notification.request.content.userInfo).historyKeys
                return !keys.isEmpty && keys.allSatisfy(isRead) ? notification.request.identifier : nil
            }
            if !identifiers.isEmpty { center.removeDeliveredNotifications(withIdentifiers: identifiers) }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let payload = NotificationPayload(userInfo: response.notification.request.content.userInfo)
        let identifier = response.actionIdentifier
        guard identifier != UNNotificationDismissActionIdentifier else { return }
        let action = NotificationAction(identifier: identifier)
        await MainActor.run {
            self.onResponse?(action, payload)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Stil binnengekomen (passief, of in de stille uren) blijft stil, ook als Pullwatch voor is.
        let content = notification.request.content
        if content.interruptionLevel == .passive { return [.list] }
        return content.sound == nil ? [.banner, .list] : [.banner, .list, .sound]
    }
}

/// Het teken van een soort melding als bijlage als er geen profielfoto is: de Octicon van de PR
/// zoals in de lijsten, of een SF Symbol, in de kleur van de soort.
nonisolated enum NotificationGlyph: Hashable, Sendable, CaseIterable {
    case pullRequest, merged, release, tag, vulnerability, securityAlert, packageUpdate

    init?(kind: NotificationKind) {
        switch kind {
        case .pullRequest: self = .pullRequest
        case .merged: self = .merged
        case .release: self = .release
        case .tag: self = .tag
        case .vulnerability: self = .vulnerability
        case .securityAlert: self = .securityAlert
        case .packageUpdate: self = .packageUpdate
        // Het icoon van Pullwatch staat er al; een tweede plaatje zegt niets.
        case .appUpdate, .account: return nil
        }
    }

    var glyph: Glyph {
        switch self {
        case .pullRequest: PRStatus.open.glyph
        case .merged: PRStatus.merged.glyph
        case .release: .system("shippingbox.fill")
        case .tag: ItemKind.tag.glyph
        case .vulnerability: .system("exclamationmark.shield.fill")
        case .securityAlert: .system("shield.lefthalf.filled")
        case .packageUpdate: .system("arrow.up.circle.fill")
        }
    }

    var color: Color {
        switch self {
        case .pullRequest: PRStatus.open.color
        case .merged: PRStatus.merged.color
        case .release, .tag: ItemKind.tag.color
        case .vulnerability: .red
        case .securityAlert: .orange
        case .packageUpdate: .blue
        }
    }

    @MainActor var view: some View {
        glyph.image
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .padding(10)
            .frame(width: 64, height: 64)
            .background(color.opacity(0.15), in: .rect(cornerRadius: 14))
    }
}
