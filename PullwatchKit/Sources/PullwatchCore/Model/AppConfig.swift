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
    /// Melding als er een nieuwe versie is van een package of runtime die een repo gebruikt.
    public var notifyPackageUpdates: Bool
    /// Melding bij een nieuwe critical- of high-melding van code scanning of Advanced Security.
    /// Standaard uit: die meldingen staan ook bij GitHub of Azure DevOps.
    public var notifySecurityAlerts: Bool
    /// Het welkomstvenster is afgerond of overgeslagen. Staat in de config (niet in de defaults),
    /// zodat een eigen datamap (`-PullwatchDataDirectory`, de UI-tests) er los van staat.
    public var onboardingCompleted: Bool

    public init(
        accounts: [Account] = [],
        pollInterval: Int = 120,
        historyRetention: HistoryRetention = .oneYear,
        autoVersionCheck: Bool = true,
        checkForUpdates: Bool = true,
        includeTestVersions: Bool = false,
        notifyPackageUpdates: Bool = true,
        notifySecurityAlerts: Bool = false,
        onboardingCompleted: Bool = false
    ) {
        self.accounts = accounts
        self.pollInterval = pollInterval
        self.historyRetention = historyRetention
        self.autoVersionCheck = autoVersionCheck
        self.checkForUpdates = checkForUpdates
        self.includeTestVersions = includeTestVersions
        self.notifyPackageUpdates = notifyPackageUpdates
        self.notifySecurityAlerts = notifySecurityAlerts
        self.onboardingCompleted = onboardingCompleted
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try c.decode([Account].self, forKey: .accounts)
        pollInterval = try c.decode(Int.self, forKey: .pollInterval)
        historyRetention = try c.decodeIfPresent(HistoryRetention.self, forKey: .historyRetention) ?? .oneYear
        autoVersionCheck = try c.decodeIfPresent(Bool.self, forKey: .autoVersionCheck) ?? true
        checkForUpdates = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? true
        includeTestVersions = try c.decodeIfPresent(Bool.self, forKey: .includeTestVersions) ?? false
        notifyPackageUpdates = try c.decodeIfPresent(Bool.self, forKey: .notifyPackageUpdates) ?? true
        notifySecurityAlerts = try c.decodeIfPresent(Bool.self, forKey: .notifySecurityAlerts) ?? false
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
    }

    public var clampedInterval: Int {
        min(max(pollInterval, Self.intervalRange.lowerBound), Self.intervalRange.upperBound)
    }

    /// Accounts die net zijn toegevoegd en nog geen organisatie hebben, worden niet gepold.
    /// Accounts die Pullwatch ophaalt: met een eigenaar en niet uitgezet.
    public var pollableAccounts: [Account] {
        accounts.filter { $0.isComplete && !$0.isPaused }
    }
}
