public import Foundation

/// Een open PR die uit de rij ging zonder te mergen (`MergeQueueEntry`): uit de merge queue of
/// merge train gehaald, of auto-merge of auto-complete uitgezet. `PollEngine` ziet het aan twee
/// polls na elkaar; de reden alleen als de dienst die geeft (GitHub).
public struct MergeQueueExit: Codable, Hashable, Sendable {
    /// Uit welke rij de PR ging.
    public var kind: MergeQueueEntry.Kind
    /// Wanneer Pullwatch het zag.
    public var at: Date
    /// De reden zoals de dienst hem geeft (in zijn eigen taal); nil als die er niet is.
    public var reason: String?

    public init(kind: MergeQueueEntry.Kind, at: Date, reason: String? = nil) {
        self.kind = kind
        self.at = at
        self.reason = reason
    }
}
