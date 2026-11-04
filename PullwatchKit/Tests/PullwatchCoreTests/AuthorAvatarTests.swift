import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// De foto van de auteur van een PR: wat de API gaf, bewaard in de geschiedenis, en de gok op
/// github.com alleen als die er niet is en de auteur geen bot is.
@Suite struct AuthorAvatarTests {
    let bot = URL(string: "https://avatars.githubusercontent.com/in/15368?v=4")!
    let mona = URL(string: "https://avatars.githubusercontent.com/u/1?v=4")!

    func pr(number: Int = 1, author: String = "github-actions[bot]", avatar: URL?) -> PullRequest {
        var pr = PullRequest.fixture(number: number, authorId: author, authorName: author)
        pr.authorAvatarURL = avatar
        return pr
    }

    // MARK: - Opslaan

    @Test func `A pull request from history without the avatar field decodes with none`() throws {
        let json = #"{"accountId":"00000000-0000-0000-0000-000000000001","repo":"proj/api","number":7,"title":"Oud","authorId":"a","authorName":"A","isDraft":false,"createdAt":1760000000,"webURL":"https://example.com/pr/7","state":"merged","coAuthors":[]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let pr = try decoder.decode(PullRequest.self, from: Data(json.utf8))
        #expect(pr.authorAvatarURL == nil)
        #expect(pr.state == .merged)
    }

    @Test func `The avatar URL survives a round trip through JSON`() throws {
        let original = pr(avatar: bot)
        let decoded = try JSONDecoder().decode(PullRequest.self, from: JSONEncoder().encode(original))
        #expect(decoded.authorAvatarURL == bot)
        #expect(decoded == original)
    }

    @Test func `Two pull requests that differ only in avatar are not equal`() {
        #expect(pr(avatar: bot) != pr(avatar: nil))
    }

    @Test func `A history entry of a pull request gives its avatar`() {
        #expect(HistoryEntry.pullRequest(pr(avatar: bot)).authorAvatarURL == bot)
    }

    // MARK: - Samenvoegen

    @Test func `A synced pull request gives a stored one without avatar its avatar`() throws {
        var history = History()
        history.add(pullRequests: [pr(avatar: nil)], tags: [], at: .testStart)

        let changed = history.merge(synced: [pr(avatar: bot)])

        #expect(changed)
        #expect(history.items.count == 1)
        #expect(history.items[0].entry.authorAvatarURL == bot)
        #expect(!history.items[0].isRead, "samenvoegen laat de gelezen-status staan")
    }

    @Test func `A synced pull request without avatar keeps the stored one`() {
        var history = History()
        history.add(pullRequests: [pr(avatar: bot)], tags: [], at: .testStart)

        let changed = history.merge(synced: [pr(avatar: nil)])

        #expect(!changed)
        #expect(history.items[0].entry.authorAvatarURL == bot)
    }

    @Test func `A newer avatar URL replaces the stored one`() {
        var history = History()
        history.add(pullRequests: [pr(author: "mona", avatar: URL(string: "https://avatars.githubusercontent.com/u/1?v=3"))], tags: [], at: .testStart)

        let changed = history.merge(synced: [pr(author: "mona", avatar: mona)])

        #expect(changed)
        #expect(history.items[0].entry.authorAvatarURL == mona)
    }

    // MARK: - Welke foto

    @Test func `The avatar from the API wins over the guess`() {
        #expect(Account.authorAvatarURL(bot, login: "github-actions[bot]", kind: .gitHub, size: 40) == bot)
        #expect(Account.authorAvatarURL(mona, login: "mona", kind: .gitHub, size: 40) == mona)
        #expect(Account.authorAvatarURL(mona, login: "Mona Lisa", kind: .azureDevOps, size: 40) == mona)
    }

    @Test(arguments: ["github-actions[bot]", "renovate[bot]", "dependabot[bot]"])
    func `A bot without an avatar from the API gets no guess`(_ login: String) {
        #expect(Account.authorAvatarURL(nil, login: login, kind: .gitHub, size: 40) == nil)
    }

    @Test func `A person without an avatar from the API gets the github.com guess`() {
        #expect(Account.authorAvatarURL(nil, login: "mona", kind: .gitHub, size: 40)
                == URL(string: "https://github.com/mona.png?size=40"))
        #expect(Account.authorAvatarURL(nil, login: "mona", kind: .gitHub, size: 40, web: URL(string: "https://github.example.com"))
                == URL(string: "https://github.example.com/mona.png?size=40"))
    }

    @Test func `Without an avatar from the API a name with spaces or another service gets none`() {
        #expect(Account.authorAvatarURL(nil, login: "Mona Lisa", kind: .gitHub, size: 40) == nil)
        #expect(Account.authorAvatarURL(nil, login: "mona", kind: .gitLab, size: 40) == nil)
        #expect(Account.authorAvatarURL(nil, login: "mona", kind: .azureDevOps, size: 40) == nil)
    }
}
