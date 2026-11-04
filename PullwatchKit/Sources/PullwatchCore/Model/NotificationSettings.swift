import Foundation

/// De soorten meldingen die Pullwatch geeft. Elke soort heeft een eigen schakelaar onder
/// Instellingen > Meldingen (behalve de update van Pullwatch en een account dat niet meer inlogt).
public enum NotificationKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case pullRequest, merged, release, tag, vulnerability, securityAlert, packageUpdate
    /// De checks van een eigen open PR mislukten.
    case checksFailed
    /// Een nieuwere Pullwatch.
    case appUpdate
    /// Een account waarvan het token niet meer werkt.
    case account

    public var id: Self { self }

    /// De soorten met een eigen schakelaar, in de volgorde van de instellingen.
    static let switchable: [NotificationKind] = [
        .pullRequest, .merged, .checksFailed, .release, .tag, .vulnerability, .securityAlert, .packageUpdate,
    ]
}

/// Hoe hard een melding binnenkomt: `passive` komt alleen in het Berichtencentrum, `active`
/// toont een banner. `UNNotificationInterruptionLevel.timeSensitive` gebruikt Pullwatch niet:
/// dat vraagt het recht `com.apple.developer.usernotifications.time-sensitive`, dat op macOS
/// alleen met een provisioning profile werkt (zie docs/setup.md).
public enum NotificationLevel: String, Codable, Sendable, Comparable {
    case passive, active

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs == .passive && rhs == .active }
}

/// Een tijdvak waarin meldingen stil binnenkomen: geen geluid, en alleen in het Berichtencentrum.
/// Focus en Niet storen regelt macOS zelf; dit is voor wie Pullwatch 's avonds stil wil zonder
/// de rest van de Mac. Begin en eind in minuten na middernacht; een eind vóór het begin loopt
/// over middernacht door.
public struct QuietHours: Codable, Equatable, Sendable {
    public var isOn: Bool
    public var start: Int
    public var end: Int

    public init(isOn: Bool = false, start: Int = 22 * 60, end: Int = 7 * 60) {
        self.isOn = isOn
        self.start = Self.clamp(start)
        self.end = Self.clamp(end)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isOn: try c.decodeIfPresent(Bool.self, forKey: .isOn) ?? false,
            start: try c.decodeIfPresent(Int.self, forKey: .start) ?? 22 * 60,
            end: try c.decodeIfPresent(Int.self, forKey: .end) ?? 7 * 60
        )
    }

    private static func clamp(_ minutes: Int) -> Int { min(max(minutes, 0), 24 * 60 - 1) }

    /// Valt `date` in de stille uren? Begin telt mee, eind niet; begin gelijk aan eind is nooit.
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isOn, start != end else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return start < end ? (start..<end).contains(minute) : minute >= start || minute < end
    }
}

/// Alles over meldingen, onder Instellingen > Meldingen. Wat per repo wel of niet meldt staat
/// bij de repo zelf (`WatchSet.notifyPRs` en verder); dit is de schakelaar per soort daarboven.
public struct NotificationSettings: Codable, Equatable, Sendable {
    public var pullRequests: Bool
    public var merged: Bool
    /// Standaard uit: mislukte checks van je eigen PR's.
    public var checksFailed: Bool
    public var releases: Bool
    public var tags: Bool
    public var vulnerabilities: Bool
    /// Standaard uit: die meldingen staan ook bij GitHub of Azure DevOps.
    public var securityAlerts: Bool
    public var packageUpdates: Bool
    /// De melding van een nieuwe versie alleen als een repo hem nu binnen zijn bereik kan nemen.
    public var onlyUpdatesYouCanTake: Bool
    public var quietHours: QuietHours
    /// Het aantal ongelezen op het Dock-icoon, zolang er een venster open is.
    public var dockBadge: Bool
    /// Een stip naast het icoon in de menubalk zolang er iets ongelezen is.
    public var menuBarDot: Bool

    public init(
        pullRequests: Bool = true, merged: Bool = true, checksFailed: Bool = false, releases: Bool = true, tags: Bool = true,
        vulnerabilities: Bool = true, securityAlerts: Bool = false, packageUpdates: Bool = true,
        onlyUpdatesYouCanTake: Bool = true, quietHours: QuietHours = QuietHours(),
        dockBadge: Bool = true, menuBarDot: Bool = true
    ) {
        self.pullRequests = pullRequests
        self.merged = merged
        self.checksFailed = checksFailed
        self.releases = releases
        self.tags = tags
        self.vulnerabilities = vulnerabilities
        self.securityAlerts = securityAlerts
        self.packageUpdates = packageUpdates
        self.onlyUpdatesYouCanTake = onlyUpdatesYouCanTake
        self.quietHours = quietHours
        self.dockBadge = dockBadge
        self.menuBarDot = menuBarDot
    }

    /// Elk veld dat ontbreekt krijgt zijn standaard, zodat een latere instelling erbij kan.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = NotificationSettings()
        func value(_ key: CodingKeys, _ fallback: Bool) throws -> Bool {
            try c.decodeIfPresent(Bool.self, forKey: key) ?? fallback
        }
        pullRequests = try value(.pullRequests, defaults.pullRequests)
        merged = try value(.merged, defaults.merged)
        checksFailed = try value(.checksFailed, defaults.checksFailed)
        releases = try value(.releases, defaults.releases)
        tags = try value(.tags, defaults.tags)
        vulnerabilities = try value(.vulnerabilities, defaults.vulnerabilities)
        securityAlerts = try value(.securityAlerts, defaults.securityAlerts)
        packageUpdates = try value(.packageUpdates, defaults.packageUpdates)
        onlyUpdatesYouCanTake = try value(.onlyUpdatesYouCanTake, defaults.onlyUpdatesYouCanTake)
        quietHours = try c.decodeIfPresent(QuietHours.self, forKey: .quietHours) ?? defaults.quietHours
        dockBadge = try value(.dockBadge, defaults.dockBadge)
        menuBarDot = try value(.menuBarDot, defaults.menuBarDot)
    }

    /// Staat de melding van deze soort aan? Een update van Pullwatch en een account dat niet
    /// meer inlogt melden altijd.
    public subscript(kind: NotificationKind) -> Bool {
        get {
            switch kind {
            case .pullRequest: pullRequests
            case .merged: merged
            case .checksFailed: checksFailed
            case .release: releases
            case .tag: tags
            case .vulnerability: vulnerabilities
            case .securityAlert: securityAlerts
            case .packageUpdate: packageUpdates
            case .appUpdate, .account: true
            }
        }
        set {
            switch kind {
            case .pullRequest: pullRequests = newValue
            case .merged: merged = newValue
            case .checksFailed: checksFailed = newValue
            case .release: releases = newValue
            case .tag: tags = newValue
            case .vulnerability: vulnerabilities = newValue
            case .securityAlert: securityAlerts = newValue
            case .packageUpdate: packageUpdates = newValue
            case .appUpdate, .account: break
            }
        }
    }
}
