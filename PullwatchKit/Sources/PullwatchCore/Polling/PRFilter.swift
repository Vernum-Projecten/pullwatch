import Foundation

/// Welke pull requests van een account gevolgd en gemeld worden.
enum PRFilter {
    public static func follows(repo: String, settings: FilterSettings) -> Bool {
        settings.watch(for: repo).prs
    }

    /// `watching` kiest welk vinkje de repo moet hebben: PR's (standaard) of completed.
    static func passes(
        _ pr: PullRequest,
        settings: FilterSettings,
        currentUserId: String?,
        watching field: KeyPath<WatchSet, Bool> = \.prs
    ) -> Bool {
        guard settings.watch(for: pr.repo)[keyPath: field] else { return false }
        if pr.isDraft && !settings.includeDrafts { return false }
        if settings.hideOwn, let me = currentUserId,
           pr.authorId.caseInsensitiveCompare(me) == .orderedSame {
            return false
        }
        return true
    }
}
