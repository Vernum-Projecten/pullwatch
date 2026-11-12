public import Foundation

/// Eén gemelde push naar een branch van een gevolgde repo.
public struct BranchPush: Codable, Hashable, Identifiable, Sendable {
    /// `.recent` is de seed-rij (laatste commit in de afgelopen 14 dagen); `.newBranch` een branch
    /// die na het seeden verscheen.
    public enum Kind: String, Codable, Sendable { case push, forcePush, newBranch, recent }

    public let accountId: UUID
    public let repo: String
    public let branch: String
    public let oldSha: String?
    public let newSha: String
    /// `nil`: onbekend of niet van toepassing.
    public let commits: Int?
    public let kind: Kind
    public let authorName: String?
    public let authorAvatarURL: URL?
    public let isOwn: Bool
    /// Detectietijd, bij `.recent` de commitdatum.
    public let pushedAt: Date
    /// De vergelijking, of de branch als er geen oude sha is.
    public let webURL: URL

    public var id: String { "\(accountId.uuidString):\(repo.lowercased()):\(branch):\(newSha)" }

    public init(
        accountId: UUID, repo: String, branch: String, oldSha: String? = nil, newSha: String, commits: Int? = nil,
        kind: Kind, authorName: String? = nil, authorAvatarURL: URL? = nil, isOwn: Bool, pushedAt: Date, webURL: URL
    ) {
        self.accountId = accountId
        self.repo = repo
        self.branch = branch
        self.oldSha = oldSha
        self.newSha = newSha
        self.commits = commits
        self.kind = kind
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
        self.isOwn = isOwn
        self.pushedAt = pushedAt
        self.webURL = webURL
    }
}
