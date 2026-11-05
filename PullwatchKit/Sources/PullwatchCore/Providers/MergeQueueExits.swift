/// Wat een dienst zegt over PR's die net uit de rij gingen (`PRProvider.mergeQueueExits(of:)`).
public struct MergeQueueExits: Equatable, Sendable {
    /// De reden per dedupKey, zoals de dienst hem geeft.
    public var reasons: [String: String]
    /// PR's (dedupKeys) die volgens de dienst toch niet zonder mergen uit de rij gingen: inmiddels
    /// gemerged of gesloten, of weer in de rij. Die melden niet.
    public var notLeft: Set<String>

    public init(reasons: [String: String] = [:], notLeft: Set<String> = []) {
        self.reasons = reasons
        self.notLeft = notLeft
    }
}
