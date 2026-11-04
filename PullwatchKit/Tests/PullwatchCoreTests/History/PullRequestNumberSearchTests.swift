import Foundation
import PullwatchCore
import PullwatchTestSupport
import Testing

/// Zoeken op het nummer van een PR (#193): `1570`, `#1570`, `!42`, `FerroFED#1570` en
/// `FerroHEALTH/FerroFED#1570` vinden die PR; de titel blijft doorzocht.
@Suite struct PullRequestNumberSearchTests {
    static let gitHub = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    static let gitLab = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    static let azure = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!
    let kinds: [UUID: ProviderKind] = [gitHub: .gitHub, gitLab: .gitLab, azure: .azureDevOps]
    let history: History

    init() {
        var history = History()
        history.add(
            pullRequests: [
                .fixture(accountId: Self.gitHub, repo: "FerroHEALTH/FerroFED", number: 1570, title: "Add the export"),
                .fixture(accountId: Self.gitHub, repo: "FerroHEALTH/FerroAPI", number: 1570, title: "Bump the client"),
                .fixture(accountId: Self.gitHub, repo: "FerroHEALTH/FerroFED", number: 15, title: "Revert 1570 for now"),
                .fixture(accountId: Self.gitLab, repo: "group/sub/project", number: 42, title: "Merge the pipeline"),
                .fixture(accountId: Self.azure, repo: "project/repo", number: 42, title: "Tidy up"),
                .fixture(accountId: Self.gitHub, repo: "octo/app", number: 42, title: "Answer"),
            ],
            tags: [.fixture(accountId: Self.gitHub, repo: "FerroHEALTH/FerroFED", name: "v1570")],
            at: .testStart
        )
        self.history = history
    }

    /// De gevonden PR's als `repo<teken>nummer`, op volgorde van de verwijzing.
    func found(_ text: String) -> [String] {
        history.search(text, kind: .pullRequest, providerKinds: kinds).compactMap { item in
            guard case .pullRequest(let pr) = item.entry, let kind = kinds[pr.accountId] else { return nil }
            return pr.reference(kind)
        }
        .sorted()
    }

    @Test(arguments: [
        ("1570", ["FerroHEALTH/FerroAPI#1570", "FerroHEALTH/FerroFED#15", "FerroHEALTH/FerroFED#1570"]),
        ("#1570", ["FerroHEALTH/FerroAPI#1570", "FerroHEALTH/FerroFED#1570"]),
        ("FerroFED#1570", ["FerroHEALTH/FerroFED#1570"]),
        ("ferrofed #1570", ["FerroHEALTH/FerroFED#1570"]),
        ("FerroHEALTH/FerroFED#1570", ["FerroHEALTH/FerroFED#1570"]),
        ("!42", ["group/sub/project!42", "project/repo!42"]),
        ("#42", ["octo/app#42"]),
        ("project!42", ["group/sub/project!42"]),
        ("sub/project!42", ["group/sub/project!42"]),
        ("group/sub/project!42", ["group/sub/project!42"]),
        ("repo!42", ["project/repo!42"]),
        ("FerroAPI#15", []),
        ("Merge the", ["group/sub/project!42"]),
    ])
    func `Finds a pull request by its number`(text: String, expected: [String]) {
        #expect(found(text) == expected)
    }

    @Test func `A bare number still finds titles`() {
        #expect(found("1570").contains("FerroHEALTH/FerroFED#15"))
    }

    @Test(arguments: ["", "#", "abc#", "#12a", "#-1", "#0", "12 34"])
    func `Text without a pull request number is no number query`(text: String) {
        #expect(PullRequestNumberQuery(text) == nil)
    }

    @Test func `Without the service of the account the sign does not count`() {
        let pr = PullRequest.fixture(repo: "group/app", number: 7)

        #expect(PullRequestNumberQuery("#7")?.matches(pr, kind: nil) == true)
        #expect(PullRequestNumberQuery("!7")?.matches(pr, kind: nil) == true)
        #expect(PullRequestNumberQuery("#7")?.matches(pr, kind: .gitLab) == false)
    }
}
