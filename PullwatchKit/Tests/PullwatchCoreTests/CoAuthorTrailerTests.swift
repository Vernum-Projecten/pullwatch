import Foundation
import Testing
@testable import PullwatchCore

@Suite struct CoAuthorTrailerTests {
    @Test(arguments: [
        "Co-authored-by: Mona Lisa <mona@example.com>",
        "co-authored-by: Mona Lisa <mona@example.com>",
        "CO-AUTHORED-BY:Mona Lisa <mona@example.com>",
        "  Co-Authored-By :  Mona Lisa   <mona@example.com>  ",
    ])
    func keyIsCaseInsensitiveAndSpacingIsTrimmed(line: String) throws {
        let person = try #require(CoAuthorTrailer.parse(line: line))
        #expect(person == Person(name: "Mona Lisa", email: "mona@example.com"))
    }

    @Test(arguments: [
        "Co-authored-by: Mona Lisa",
        "Co-authored-by: <mona@example.com>",
        "Co-authored-by: Mona Lisa <not an email>",
        "Co-authored-by: Mona Lisa <mona>",
        "Co-authored-by: Mona Lisa >mona@example.com<",
        "Signed-off-by: Mona Lisa <mona@example.com>",
        "Co-authored: Mona Lisa <mona@example.com>",
        "",
    ])
    func malformedLinesAreIgnored(line: String) {
        #expect(CoAuthorTrailer.parse(line: line) == nil)
    }

    @Test func noreplyAddressGivesTheLogin() throws {
        let numbered = try #require(CoAuthorTrailer.parse(line: "Co-authored-by: Octo Cat <583231+octocat@users.noreply.github.com>"))
        #expect(numbered.login == "octocat")
        let plain = try #require(CoAuthorTrailer.parse(line: "Co-authored-by: Octo Cat <octocat@users.noreply.github.com>"))
        #expect(plain.login == "octocat")
        #expect(CoAuthorTrailer.parse(line: "Co-authored-by: Octo <octo@example.com>")?.login == nil)
    }

    @Test func peopleInMessageReadsEveryTrailerInOrder() {
        let message = """
            Add the Dutch greeting

            Some body text with Co-authored-by: in the middle of a line.

            Co-authored-by: Mona <mona@example.com>
            co-authored-by: Hubot <hubot@example.com>\r
            Co-authored-by: broken line
            """
        #expect(CoAuthorTrailer.people(in: message).map(\.name) == ["Mona", "Hubot"])
    }

    @Test func duplicatesAreMergedByEmailIgnoringCase() {
        let people = CoAuthorTrailer.coAuthors(from: [
            Person(name: "Mona", email: "mona@example.com"),
            Person(name: "Mona Lisa", email: "MONA@example.com"),
            Person(name: "Hubot", email: "hubot@example.com"),
        ], author: ["jdoe"])
        #expect(people.map(\.name) == ["Mona", "Hubot"])
    }

    @Test func laterMentionFillsInLoginAndAvatar() {
        let avatar = URL(string: "https://avatars.example.com/mona")!
        let people = CoAuthorTrailer.coAuthors(from: [
            Person(name: "Mona", email: "mona@example.com"),
            Person(name: "Mona", login: "mona", email: "mona@example.com", avatarURL: avatar),
            Person(name: "Mona", email: "1+mona@users.noreply.github.com"),
        ], author: [])
        #expect(people == [Person(name: "Mona", login: "mona", email: "mona@example.com", avatarURL: avatar)])
    }

    @Test func sameNameWithDifferentEmailsStaysTwoPeople() {
        let people = CoAuthorTrailer.coAuthors(from: [
            Person(name: "Jan", email: "jan@one.example"),
            Person(name: "Jan", email: "jan@two.example"),
        ], author: [])
        #expect(people.count == 2)
    }

    @Test func authorIsSkippedByLoginEmailOrName() {
        let people = CoAuthorTrailer.coAuthors(from: [
            Person(name: "Octo Cat", login: "octocat", email: "octo@example.com"),
            Person(name: "Octo Cat", email: "583231+OctoCat@users.noreply.github.com"),
            Person(name: "Jan Jansen", email: "jan@example.com"),
            Person(name: "Other", email: "jan.jansen@example.com"),
            Person(name: "Mona", email: "mona@example.com"),
        ], author: ["octocat", "Jan Jansen", "JAN.JANSEN@example.com"])
        #expect(people.map(\.name) == ["Mona"])
    }

    @Test func botsAreSkipped() {
        let people = CoAuthorTrailer.coAuthors(from: [
            Person(name: "dependabot[bot]", email: "49699333+dependabot[bot]@users.noreply.github.com"),
            Person(name: "GitHub Actions", login: "github-actions[bot]"),
            Person(name: "Renovate", email: "29139614+renovate[bot]@users.noreply.github.com"),
            Person(name: "Mona", email: "mona@example.com"),
        ], author: [])
        #expect(people.map(\.name) == ["Mona"])
    }
}
