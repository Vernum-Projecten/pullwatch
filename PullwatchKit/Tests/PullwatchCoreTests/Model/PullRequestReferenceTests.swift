import Foundation
import PullwatchCore
import PullwatchTestSupport
import Testing

/// Het nummer van een PR zoals elke dienst het schrijft (#193): `#` op GitHub, `!` op GitLab en
/// Azure DevOps, met de verwijzing voluit en kort.
@Suite struct PullRequestReferenceTests {
    @Test(arguments: [
        (ProviderKind.gitHub, "#"),
        (.gitLab, "!"),
        (.azureDevOps, "!"),
    ])
    func `Each service writes the number with its own sign`(kind: ProviderKind, prefix: String) {
        #expect(kind.pullRequestPrefix == prefix)
    }

    @Test func `Every service has a sign of one character`() {
        for kind in ProviderKind.allCases {
            #expect(["#", "!"].contains(kind.pullRequestPrefix), "\(kind)")
        }
    }

    @Test(arguments: [
        (ProviderKind.gitHub, "FerroHEALTH/FerroFED", 1570, "FerroHEALTH/FerroFED#1570", "FerroFED #1570", "FerroHEALTH/FerroFED #1570", "#1570"),
        (.gitLab, "group/sub/project", 42, "group/sub/project!42", "project !42", "group/sub/project !42", "!42"),
        (.azureDevOps, "project/repo", 42, "project/repo!42", "repo !42", "project/repo !42", "!42"),
    ])
    func `The reference per service`(
        kind: ProviderKind, repo: String, number: Int, reference: String, short: String, withRepo: String, numberText: String
    ) {
        let pr = PullRequest.fixture(repo: repo, number: number)

        #expect(pr.reference(kind) == reference)
        #expect(pr.shortReference(kind) == short)
        #expect(pr.repoAndNumber(kind) == withRepo)
        #expect(pr.numberText(kind) == numberText)
        #expect(HistoryEntry.pullRequest(pr).reference(kind) == reference)
    }

    @Test func `A tag has no reference`() {
        let tag = HistoryEntry.tag(.fixture(name: "v1.0.0"))

        #expect(tag.reference(.gitHub) == nil)
        #expect(tag.pullRequestNumber == nil)
    }

    @Test(arguments: [("FerroHEALTH/FerroFED", "FerroFED"), ("group/sub/project", "project"), ("solo", "solo")])
    func `The short name is the last part of the path`(repo: String, short: String) {
        #expect(PullRequest.shortName(of: repo) == short)
    }
}
