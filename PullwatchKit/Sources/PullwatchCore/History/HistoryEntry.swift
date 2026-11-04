import Foundation

/// Eén item in de geschiedenis: een pull request of een tag.
public enum HistoryEntry: Codable, Hashable, Sendable {
    case pullRequest(PullRequest)
    case tag(Tag)

    public var kind: ItemKind {
        switch self {
        case .pullRequest: return .pullRequest
        case .tag: return .tag
        }
    }

    public var dedupKey: String {
        switch self {
        case .pullRequest(let pr): return pr.dedupKey
        case .tag(let tag): return tag.dedupKey
        }
    }

    public var accountId: UUID {
        switch self {
        case .pullRequest(let pr): return pr.accountId
        case .tag(let tag): return tag.accountId
        }
    }

    public var repo: String {
        switch self {
        case .pullRequest(let pr): return pr.repo
        case .tag(let tag): return tag.repo
        }
    }

    /// PR-titel of tagnaam.
    public var title: String {
        switch self {
        case .pullRequest(let pr): return pr.title
        case .tag(let tag): return tag.name
        }
    }

    public var author: String? {
        switch self {
        case .pullRequest(let pr): return pr.authorName
        case .tag(let tag): return tag.authorName
        }
    }

    /// Co-auteurs van een PR; leeg voor tags.
    public var coAuthors: [Person] {
        switch self {
        case .pullRequest(let pr): return pr.coAuthors
        case .tag: return []
        }
    }

    /// Foto van de auteur zoals de provider hem gaf (PR of tag); `nil` als die er niet is.
    public var authorAvatarURL: URL? {
        switch self {
        case .pullRequest(let pr): return pr.authorAvatarURL
        case .tag(let tag): return tag.authorAvatarURL
        }
    }

    /// De release bij een tag; `nil` voor PR's en tags zonder release.
    public var release: ReleaseInfo? {
        switch self {
        case .pullRequest: return nil
        case .tag(let tag): return tag.release
        }
    }

    /// De titel van de release bij een tag, als die iets anders zegt dan de tagnaam.
    public var releaseTitle: String? {
        switch self {
        case .pullRequest: return nil
        case .tag(let tag): return tag.releaseTitle
        }
    }

    public var webURL: URL {
        switch self {
        case .pullRequest(let pr): return pr.webURL
        case .tag(let tag): return tag.webURL
        }
    }

    /// De checks van een PR; `nil` voor tags en voor een PR zonder opgehaalde checks.
    public var checks: PRChecks? {
        switch self {
        case .pullRequest(let pr): return pr.checks
        case .tag: return nil
        }
    }

    /// Status van de PR; `nil` voor tags.
    public var prState: PRState? {
        switch self {
        case .pullRequest(let pr): return pr.state
        case .tag: return nil
        }
    }
}

/// Een item in de geschiedenis met wanneer Pullwatch het zag en of het gelezen is.
public struct HistoryItem: Codable, Identifiable, Hashable, Sendable {
    public var entry: HistoryEntry
    public var detectedAt: Date
    public var isRead: Bool

    public var id: String { entry.dedupKey }

    public init(entry: HistoryEntry, detectedAt: Date, isRead: Bool) {
        self.entry = entry
        self.detectedAt = detectedAt
        self.isRead = isRead
    }
}
