import Foundation

/// Hoe één check (een GitHub-check-run of commit-status, een Azure DevOps-status of
/// build-policy, een GitLab-job) ervoor staat, teruggebracht tot wat de telling nodig heeft.
public enum CheckOutcome: Sendable, Equatable {
    /// Geslaagd.
    case passed
    /// Overgeslagen of neutraal: telt als geslaagd, zoals GitHub dat doet.
    case skipped
    /// Mislukt, fout, te lang bezig, geannuleerd of wacht op een handeling.
    case failed
    /// Nog in de wachtrij of bezig.
    case pending
}

/// De stand van alle checks samen: rood zodra er één mislukte, anders geel zolang er nog iets
/// loopt, anders groen.
public enum CheckState: String, Codable, Sendable, CaseIterable {
    case passed, failed, pending
}

/// Hoeveel checks van een PR in welke stand zijn, op de laatste commit van de PR.
public struct CheckCounts: Codable, Hashable, Sendable {
    public var passed: Int
    public var skipped: Int
    public var failed: Int
    public var pending: Int

    public init(passed: Int = 0, skipped: Int = 0, failed: Int = 0, pending: Int = 0) {
        self.passed = passed
        self.skipped = skipped
        self.failed = failed
        self.pending = pending
    }

    /// Telt elke uitkomst één keer.
    public init(_ outcomes: some Sequence<CheckOutcome>) {
        self.init()
        for outcome in outcomes { add(outcome) }
    }

    public mutating func add(_ outcome: CheckOutcome, count: Int = 1) {
        switch outcome {
        case .passed: passed += count
        case .skipped: skipped += count
        case .failed: failed += count
        case .pending: pending += count
        }
    }

    public var total: Int { passed + skipped + failed + pending }

    /// Geslaagd in de telling "8/8": overgeslagen en neutraal tellen mee, zoals op GitHub.
    public var succeeded: Int { passed + skipped }

    /// De stand van het geheel; nil zonder checks (dan geen cel).
    public var state: CheckState? {
        guard total > 0 else { return nil }
        if failed > 0 { return .failed }
        if pending > 0 { return .pending }
        return .passed
    }
}

/// Wat Pullwatch van de checks van een PR weet.
public enum PRChecks: Codable, Hashable, Sendable {
    /// De telling (ook nul: de PR heeft geen checks).
    case counts(CheckCounts)
    /// De dienst weigert de checks te geven: de GitHub App mist het recht (Checks en Commit
    /// statuses, lezen) of het token de scope. Geen cel, wel een opmerking.
    case needsPermission

    public var counts: CheckCounts? {
        if case .counts(let counts) = self { return counts }
        return nil
    }

    /// De stand; nil zonder checks of zonder toestemming.
    public var state: CheckState? { counts?.state }
}
