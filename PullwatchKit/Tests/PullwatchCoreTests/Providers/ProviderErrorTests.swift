import Foundation
import Testing
@testable import PullwatchCore

@Suite struct ProviderErrorTests {
    @Test(arguments: [
        ("nl", "gh reageert niet op tijd"),
        ("en", "gh did not answer in time"),
        ("de", "gh hat nicht rechtzeitig geantwortet"),
        ("fr", "gh n'a pas répondu à temps"),
    ])
    func `A timeout names the command in every language`(language: String, expected: String) {
        #expect(ProviderError.timeout(command: "gh").userMessage(bundle: .core(for: language)) == expected)
    }

    @Test func `A timeout is equal only for the same command`() {
        #expect(ProviderError.timeout(command: "az") == .timeout(command: "az"))
        #expect(ProviderError.timeout(command: "az") != .timeout(command: "glab"))
        #expect(ProviderError.timeout(command: "az") != .network("az"))
    }

    @Test func `The message follows the app language by default`() {
        let error = ProviderError.timeout(command: "glab")
        #expect(error.userMessage == error.userMessage(bundle: .localizedCore))
    }
}
