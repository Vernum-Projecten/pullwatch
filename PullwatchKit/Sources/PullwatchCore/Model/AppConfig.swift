import Foundation

public struct AppConfig: Codable, Equatable, Sendable {
    public static let intervalRange = 60...900

    public var accounts: [Account]
    public var pollInterval: Int
    public var historyRetention: HistoryRetention
    /// Versies en CVE's eens per dag vanzelf checken, met melding bij nieuwe CVE's.
    public var autoVersionCheck: Bool
    /// Eens per dag kijken of er een nieuwere Pullwatch op GitHub staat.
    public var checkForUpdates: Bool
    /// Ook testversies (pre-releases, Sparkle's `beta`-kanaal) aanbieden. Standaard uit.
    public var includeTestVersions: Bool
    /// Instellingen > Meldingen: per soort aan of uit, stille uren en de badges.
    public var notifications: NotificationSettings
    /// Het welkomstvenster is afgerond of overgeslagen. Staat in de config (niet in de defaults),
    /// zodat een eigen datamap (`-PullwatchDataDirectory`, de UI-tests) er los van staat.
    public var onboardingCompleted: Bool
    /// Bronnen die de gebruiker heeft uitgezet. Standaard staat elke bron aan.
    public var disabledSources: Set<DataSourceID>

    public init(
        accounts: [Account] = [],
        pollInterval: Int = 120,
        historyRetention: HistoryRetention = .oneYear,
        autoVersionCheck: Bool = true,
        checkForUpdates: Bool = true,
        includeTestVersions: Bool = false,
        notifyPackageUpdates: Bool? = nil,
        notifyOnlyUpdatesYouCanTake: Bool? = nil,
        notifySecurityAlerts: Bool? = nil,
        notifications: NotificationSettings = NotificationSettings(),
        onboardingCompleted: Bool = false,
        disabledSources: Set<DataSourceID> = []
    ) {
        self.accounts = accounts
        self.pollInterval = pollInterval
        self.historyRetention = historyRetention
        self.autoVersionCheck = autoVersionCheck
        self.checkForUpdates = checkForUpdates
        self.includeTestVersions = includeTestVersions
        // De losse schakelaars van vroeger gaan, als ze gegeven zijn, boven `notifications`.
        var notifications = notifications
        if let notifyPackageUpdates { notifications.packageUpdates = notifyPackageUpdates }
        if let notifyOnlyUpdatesYouCanTake { notifications.onlyUpdatesYouCanTake = notifyOnlyUpdatesYouCanTake }
        if let notifySecurityAlerts { notifications.securityAlerts = notifySecurityAlerts }
        self.notifications = notifications
        self.onboardingCompleted = onboardingCompleted
        self.disabledSources = disabledSources
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try c.decode([Account].self, forKey: .accounts)
        pollInterval = try c.decode(Int.self, forKey: .pollInterval)
        historyRetention = try c.decodeIfPresent(HistoryRetention.self, forKey: .historyRetention) ?? .oneYear
        autoVersionCheck = try c.decodeIfPresent(Bool.self, forKey: .autoVersionCheck) ?? true
        checkForUpdates = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? true
        includeTestVersions = try c.decodeIfPresent(Bool.self, forKey: .includeTestVersions) ?? false
        if let notifications = try c.decodeIfPresent(NotificationSettings.self, forKey: .notifications) {
            self.notifications = notifications
        } else {
            // Van vóór Instellingen > Meldingen: de drie schakelaars van Algemeen gaan mee.
            var notifications = NotificationSettings()
            notifications.packageUpdates = try c.decodeIfPresent(Bool.self, forKey: .notifyPackageUpdates) ?? true
            notifications.onlyUpdatesYouCanTake = try c.decodeIfPresent(Bool.self, forKey: .notifyOnlyUpdatesYouCanTake) ?? true
            notifications.securityAlerts = try c.decodeIfPresent(Bool.self, forKey: .notifySecurityAlerts) ?? false
            self.notifications = notifications
        }
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        // Onbekende id's (van een nieuwere of oudere versie) worden genegeerd.
        disabledSources = Set(try c.decodeIfPresent([String].self, forKey: .disabledSources)?.compactMap(DataSourceID.init(rawValue:)) ?? [])
    }

    public func isEnabled(_ id: DataSourceID) -> Bool {
        !disabledSources.contains(id)
    }

    private enum CodingKeys: String, CodingKey {
        case accounts, pollInterval, historyRetention, autoVersionCheck, checkForUpdates, includeTestVersions
        case notifications, onboardingCompleted, disabledSources
        case notifyPackageUpdates, notifyOnlyUpdatesYouCanTake, notifySecurityAlerts
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accounts, forKey: .accounts)
        try c.encode(pollInterval, forKey: .pollInterval)
        try c.encode(historyRetention, forKey: .historyRetention)
        try c.encode(autoVersionCheck, forKey: .autoVersionCheck)
        try c.encode(checkForUpdates, forKey: .checkForUpdates)
        try c.encode(includeTestVersions, forKey: .includeTestVersions)
        try c.encode(notifications, forKey: .notifications)
        try c.encode(onboardingCompleted, forKey: .onboardingCompleted)
        // Gesorteerd, zodat config.json niet bij elke keer opslaan van volgorde wisselt.
        try c.encode(disabledSources.map(\.rawValue).sorted(), forKey: .disabledSources)
        // Nog wel geschreven: een oudere Pullwatch leest alleen deze drie.
        try c.encode(notifyPackageUpdates, forKey: .notifyPackageUpdates)
        try c.encode(notifyOnlyUpdatesYouCanTake, forKey: .notifyOnlyUpdatesYouCanTake)
        try c.encode(notifySecurityAlerts, forKey: .notifySecurityAlerts)
    }

    /// Melding als er een nieuwe versie is van een package of runtime die een repo gebruikt.
    public var notifyPackageUpdates: Bool {
        get { notifications.packageUpdates }
        set { notifications.packageUpdates = newValue }
    }

    /// Die melding alleen voor updates die een repo nu binnen zijn bereik kan nemen. Standaard aan.
    public var notifyOnlyUpdatesYouCanTake: Bool {
        get { notifications.onlyUpdatesYouCanTake }
        set { notifications.onlyUpdatesYouCanTake = newValue }
    }

    /// Melding bij een nieuwe critical- of high-melding van code scanning of Advanced Security.
    /// Standaard uit: die meldingen staan ook bij GitHub of Azure DevOps.
    public var notifySecurityAlerts: Bool {
        get { notifications.securityAlerts }
        set { notifications.securityAlerts = newValue }
    }

    public var clampedInterval: Int {
        min(max(pollInterval, Self.intervalRange.lowerBound), Self.intervalRange.upperBound)
    }

    /// De keuzes voor het poll-interval in Instellingen, in seconden.
    public static let pollIntervalChoices = [60, 120, 300, 600, 900]

    /// Het poll-interval op de dichtstbijzijnde keuze uit `pollIntervalChoices`.
    public var pollIntervalChoice: Int {
        Self.pollIntervalChoices.min { abs($0 - clampedInterval) < abs($1 - clampedInterval) } ?? clampedInterval
    }

    /// Accounts die net zijn toegevoegd en nog geen organisatie hebben, worden niet gepold.
    /// Accounts die Pullwatch ophaalt: met een eigenaar en niet uitgezet.
    public var pollableAccounts: [Account] {
        accounts.filter { $0.isComplete && !$0.isPaused }
    }
}
