package import Foundation
package import PullwatchCore

extension BranchPush {
    package static func fixture(
        accountId: UUID = fixedAccountId,
        repo: String = "proj/api",
        branch: String = "main",
        oldSha: String? = nil,
        newSha: String = "abc123",
        commits: Int? = nil,
        kind: Kind = .push,
        authorName: String? = "Someone",
        authorAvatarURL: URL? = nil,
        isOwn: Bool = false,
        pushedAt: Date = .testStart,
        webURL: URL = URL(string: "https://example.com/proj/api/tree/main")!
    ) -> BranchPush {
        BranchPush(
            accountId: accountId, repo: repo, branch: branch, oldSha: oldSha, newSha: newSha,
            commits: commits, kind: kind, authorName: authorName, authorAvatarURL: authorAvatarURL,
            isOwn: isOwn, pushedAt: pushedAt, webURL: webURL)
    }
}
