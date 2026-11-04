import Foundation

/// Wat Pullwatch op dit moment ophaalt.
public enum SyncWork: Equatable, Sendable {
    /// Een gewone poll van de accounts, op de achtergrond.
    case accounts
    /// De eerste geschiedenis-sync van een account: de lijsten vullen zich nog. Met de naam van
    /// het account dat nu aan de beurt is, als dat bekend is.
    case firstSync(account: String?)
    /// "Opnieuw ophalen": de geschiedenis van alle accounts opnieuw.
    case refetch
    /// De versiecheck van alle (of de net gevolgde) repo's.
    case versions
    /// De versiecheck van één repo.
    case repoCheck(String)

    /// Mag stoppen zonder dat er iets kapot gaat: wat al binnen is blijft.
    public var isCancellable: Bool {
        switch self {
        case .refetch, .versions: true
        case .accounts, .firstSync, .repoCheck: false
        }
    }

    /// Lang werk dat de balk onderin het hoofdvenster toont; een gewone poll alleen het menu.
    public var showsActivityBar: Bool { self != .accounts }
}

/// Eén status voor alles wat Pullwatch ophaalt, voor de balk in het hoofdvenster en de spinner
/// in het menu.
public enum SyncStatus: Equatable, Sendable {
    case idle
    /// `total == 0`: nog niet bekend hoeveel (onbepaalde voortgang).
    case syncing(done: Int, total: Int, what: SyncWork)
    /// De laatste poll mislukte voor minstens één account, met de melding erbij.
    case failed(String)

    var isSyncing: Bool {
        if case .syncing = self { true } else { false }
    }

    /// Het werk dat loopt; nil als er niets loopt.
    public var work: SyncWork? {
        if case .syncing(_, _, let what) = self { what } else { nil }
    }

    /// Kiest wat er getoond wordt als er meer tegelijk loopt: opnieuw ophalen, dan de eerste
    /// sync, dan de versiecheck (alle repo's, dan één), dan een gewone poll. Een fout alleen als
    /// er niets loopt. Een eerste sync die nog op zijn beurt wacht (`firstSyncPending`) telt als
    /// lopend, zonder aantallen.
    public static func current(
        poll: PollProgress?,
        firstSyncPending: Bool,
        refetch: (done: Int, total: Int)?,
        versions: (done: Int, total: Int)?,
        checkingRepo: String? = nil,
        failure: String?
    ) -> SyncStatus {
        if let refetch {
            return .syncing(done: refetch.done, total: refetch.total, what: .refetch)
        }
        if let poll, poll.firstSyncAccount != nil {
            return .syncing(done: poll.done, total: poll.total, what: .firstSync(account: poll.firstSyncAccount))
        }
        if firstSyncPending {
            return .syncing(done: 0, total: 0, what: .firstSync(account: nil))
        }
        if let versions {
            return .syncing(done: versions.done, total: versions.total, what: .versions)
        }
        if let checkingRepo {
            return .syncing(done: 0, total: 0, what: .repoCheck(checkingRepo))
        }
        if let poll {
            return .syncing(done: poll.done, total: poll.total, what: .accounts)
        }
        if let failure {
            return .failed(failure)
        }
        return .idle
    }
}

/// Voortgang van een check over meer repo's: hoeveel er klaar zijn van hoeveel; `total == 0`
/// is nog niet bekend hoeveel. Equatable, zodat een gelijke stand niets opnieuw laat tekenen.
public struct CheckProgress: Equatable, Sendable {
    public var done: Int
    public var total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    /// Net begonnen: nog niets gecheckt en nog niet bekend hoeveel.
    public static let starting = CheckProgress(done: 0, total: 0)
}
