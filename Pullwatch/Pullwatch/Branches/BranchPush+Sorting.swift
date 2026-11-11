import PullwatchCore

/// Sleutels om de tabel van Branches op te sorteren; hoofdletters tellen niet mee.
nonisolated extension BranchPush {
    var branchSortKey: String { branch.lowercased() }
    var repoSortKey: String { repo.lowercased() }
    var authorSortKey: String { authorName?.lowercased() ?? "" }

    /// Leeg eerst, dan een push op het aantal commits, dan een nieuwe branch en een force-push.
    var commitsSortKey: Int {
        switch kind {
        case .recent: -1
        case .push: commits ?? -1
        case .newBranch: Int.max - 1
        case .forcePush: Int.max
        }
    }
}
