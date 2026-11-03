#if DEBUG
import Foundation
import PullwatchCore
import Synchronization

/// Alleen in debug-builds, met `-PullwatchFakeGitHub YES`: een nagespeeld GitHub zonder netwerk.
/// Het speelt de device flow (eerst "wachten", dan een token), de gebruiker `octocat`, de
/// installaties (geen, tot `install()`), een paar repositories en lege zoekresultaten. De
/// UI-tests lopen er de hele inlog-flow mee door, met screenshots van elke stap.
final class FakeGitHub: HTTPClient {
    static let isEnabled = UserDefaults.standard.bool(forKey: "PullwatchFakeGitHub")
    static let shared = FakeGitHub()

    static let login = "octocat"
    static let userCode = "WDJB-MJHT"

    private struct State {
        var installed = false
        var tokenPolls = 0
    }

    /// Met `-PullwatchFakeGitHubInstalled YES` is de app al geïnstalleerd (een test-config met
    /// accounts); anders pas na `install()`, zoals bij een eerste keer inloggen.
    private let state = Mutex(State(installed: UserDefaults.standard.bool(forKey: "PullwatchFakeGitHubInstalled")))

    /// Wat er gebeurt als iemand de app op github.com installeert.
    func install() {
        state.withLock { $0.installed = true }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let path = url.path()
        let body: String
        switch path {
        case "/login/device/code":
            body = #"{"device_code":"fake-device","user_code":"\#(Self.userCode)","verification_uri":"https://github.com/login/device","expires_in":900,"interval":1}"#
        case "/login/oauth/access_token":
            let polls = state.withLock { state in
                state.tokenPolls += 1
                return state.tokenPolls
            }
            // Eerst "nog niet goedgekeurd", zoals bij iemand die de code nog intypt.
            body = polls < 8
                ? #"{"error":"authorization_pending"}"#
                : #"{"access_token":"fake-access","expires_in":28800,"refresh_token":"fake-refresh","refresh_token_expires_in":15897600}"#
        case "/user":
            body = #"{"login":"\#(Self.login)","id":1}"#
        case "/user/installations":
            body = state.withLock(\.installed)
                ? #"{"total_count":2,"installations":[{"account":{"login":"\#(Self.login)","type":"User"}},{"account":{"login":"github","type":"Organization"}}]}"#
                : #"{"total_count":0,"installations":[]}"#
        case "/users/\(Self.login)":
            body = #"{"login":"\#(Self.login)","type":"User"}"#
        case "/users/github":
            body = #"{"login":"github","type":"Organization"}"#
        case "/orgs/github/repos":
            body = #"[{"full_name":"github/docs"},{"full_name":"github/gitignore"},{"full_name":"github/linguist"}]"#
        case "/user/repos", "/users/\(Self.login)/repos":
            body = #"[{"full_name":"octocat/hello-world"},{"full_name":"octocat/spoon-knife"},{"full_name":"octocat/linguist"}]"#
        case "/search/issues":
            body = #"{"total_count":0,"items":[]}"#
        default:
            // Tags, bomen, bestanden: leeg, zodat polls en checks gewoon doorlopen.
            body = path.hasSuffix("/tags") ? "[]" : #"{"tree":[]}"#
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        return (Data(body.utf8), response)
    }
}
#endif
