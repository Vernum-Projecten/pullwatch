import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct TokenSourceTests {
    @Test func locatorFindsFirstExecutableInSearchPaths() {
        let locator = CLILocator(isExecutable: { $0 == "/usr/local/bin/gh" })
        #expect(locator.locate("gh") == URL(filePath: "/usr/local/bin/gh"))
        #expect(locator.locate("az") == nil)
    }

    @Test func staticTokenSource() async throws {
        #expect(try await StaticTokenSource(token: "x").token() == "x")
    }
}
