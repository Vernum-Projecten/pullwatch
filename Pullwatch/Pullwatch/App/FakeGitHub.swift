#if DEBUG
import Foundation
import PullwatchCore
import Synchronization

/// Alleen in debug-builds, met `-PullwatchFakeGitHub YES`: een nagespeeld GitHub zonder netwerk.
/// Het speelt de device flow (eerst "wachten", dan een token), de gebruiker `octocat`, de
/// installaties (geen, tot `install()`), een paar repositories en lege zoekresultaten. De
/// UI-tests lopen er de hele inlog-flow mee door, met screenshots van elke stap.
///
/// Met ook `-PullwatchFakeData YES` heeft `octocat` er PR's, tags en bestanden bij, en spelen
/// endoflife.date, OSV en de package-registers mee, zodat elk scherm van het hoofdvenster iets
/// te tonen heeft (`FakeWorld`).
// Een HTTP-client voor de netwerklaag (nonisolated), geen UI: niet op de main actor.
nonisolated final class FakeGitHub: HTTPClient {
    static let isEnabled = UserDefaults.standard.bool(forKey: "PullwatchFakeGitHub")
    static let hasData = UserDefaults.standard.bool(forKey: "PullwatchFakeData")
    /// Met `-PullwatchFakeDelay <seconden>` wacht elk antwoord zo lang, zodat de voortgang van
    /// een eerste sync te zien (en te fotograferen) is.
    static let delay = UserDefaults.standard.double(forKey: "PullwatchFakeDelay")
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
        if Self.delay > 0 { try await Task.sleep(for: .seconds(Self.delay)) }
        let url = request.url!
        let path = url.path()
        let body: String
        if Self.hasData, let world = FakeWorld.response(to: request) {
            body = world
        } else {
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
            case "/graphql":
                body = #"{"data":{"repository":null}}"#
            default:
                // Tags, bomen, bestanden: leeg, zodat polls en checks gewoon doorlopen.
                body = path.hasSuffix("/tags") ? "[]" : #"{"tree":[]}"#
            }
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        return (Data(body.utf8), response)
    }
}

/// De nagespeelde inhoud achter `-PullwatchFakeData`: drie repo's van octocat met PR's van
/// een paar auteurs, tags, en bestanden waarin een oude Node, een package met een nieuwe versie
/// en een bekende kwetsbaarheid zitten.
nonisolated private enum FakeWorld {
    struct PR {
        let repo: String
        let number: Int
        let title: String
        let author: String
        let daysAgo: Double
        /// "open", "merged" of "closed".
        let state: String
    }

    static let pullRequests: [PR] = [
        PR(repo: "hello-world", number: 41, title: "Bump lodash to 4.17.21", author: "dependabot[bot]", daysAgo: 0.2, state: "open"),
        PR(repo: "hello-world", number: 40, title: "Add a greeting in Dutch", author: "mona", daysAgo: 1, state: "open"),
        PR(repo: "hello-world", number: 38, title: "Move the build to Node 22", author: "hubot", daysAgo: 4, state: "merged"),
        PR(repo: "hello-world", number: 35, title: "Fix the README links", author: "mona", daysAgo: 12, state: "merged"),
        PR(repo: "hello-world", number: 31, title: "Experiment with a second greeting", author: "jdoe", daysAgo: 40, state: "closed"),
        PR(repo: "spoon-knife", number: 22, title: "Update express to the latest 4.x release", author: "hubot", daysAgo: 0.5, state: "open"),
        PR(repo: "spoon-knife", number: 21, title: "Add a fork button to the page", author: "jdoe", daysAgo: 6, state: "merged"),
        PR(repo: "spoon-knife", number: 19, title: "Clean up the stylesheet", author: "mona", daysAgo: 33, state: "merged"),
        PR(repo: "spoon-knife", number: 17, title: "Translate the page into French", author: "amelie", daysAgo: 70, state: "merged"),
        PR(repo: "linguist", number: 12, title: "Recognise Swift macros as Swift", author: "amelie", daysAgo: 2, state: "open"),
        PR(repo: "linguist", number: 11, title: "Speed up the language detection", author: "hubot", daysAgo: 20, state: "merged"),
        PR(repo: "linguist", number: 9, title: "Drop support for Go 1.20", author: "jdoe", daysAgo: 95, state: "merged"),
        PR(repo: "linguist", number: 7, title: "Add a heuristic for .h files", author: "mona", daysAgo: 150, state: "merged"),
    ]

    static let tags: [String: [String]] = [
        "hello-world": ["v1.2.0", "v1.1.0"],
        "spoon-knife": ["v3.0.1"],
        "linguist": ["v9.4.0", "v9.3.2"],
    ]

    static let files: [String: [String: String]] = [
        // Een monorepo: de root en packages/web, lodash direct (4.17.20), via express en body-parser
        // (4.17.15) en in packages/web (4.17.21), een kwetsbare qs alleen transitief en een dev-only lek.
        "hello-world": [
            ".nvmrc": "16\n",
            "package.json": #"{"name":"hello-world","workspaces":["packages/*"],"dependencies":{"lodash":"^4.17.20","express":"^4.18.0"},"devDependencies":{"jest":"^29.7.0"}}"#,
            "packages/web/package.json": #"{"name":"web","dependencies":{"lodash":"4.17.21","left-pad":"1.3.0"}}"#,
            "package-lock.json": #"{"lockfileVersion":3,"packages":{"#
                + #""":{"name":"hello-world","workspaces":["packages/*"],"dependencies":{"lodash":"^4.17.20","express":"^4.18.0"},"devDependencies":{"jest":"^29.7.0"}},"#
                + #""packages/web":{"name":"web","dependencies":{"lodash":"4.17.21","left-pad":"1.3.0"}},"#
                + #""node_modules/web":{"resolved":"packages/web","link":true},"#
                + #""node_modules/lodash":{"version":"4.17.20"},"#
                + #""node_modules/express":{"version":"4.18.0","dependencies":{"body-parser":"1.20.1"}},"#
                + #""node_modules/body-parser":{"version":"1.20.1","dependencies":{"qs":"6.10.1","lodash":"4.17.15"}},"#
                + #""node_modules/body-parser/node_modules/lodash":{"version":"4.17.15"},"#
                + #""node_modules/qs":{"version":"6.10.1"},"#
                + #""node_modules/jest":{"version":"29.7.0","dev":true,"dependencies":{"semver":"6.3.0"}},"#
                + #""node_modules/semver":{"version":"6.3.0","dev":true},"#
                + #""node_modules/left-pad":{"version":"1.3.0"},"#
                + #""packages/web/node_modules/lodash":{"version":"4.17.21"}}}"#,
        ],
        // lodash alleen via express: in Versies "alleen transitief".
        "spoon-knife": [
            ".nvmrc": "22\n",
            "package.json": #"{"name":"spoon-knife","dependencies":{"express":"^4.18.0","left-pad":"1.3.0"}}"#,
            "package-lock.json": #"{"lockfileVersion":3,"packages":{"":{"dependencies":{"express":"^4.18.0","left-pad":"1.3.0"}},"node_modules/express":{"version":"4.18.0","dependencies":{"lodash":"4.17.21"}},"node_modules/lodash":{"version":"4.17.21"},"node_modules/left-pad":{"version":"1.3.0"}}}"#,
        ],
        "linguist": [
            "go.mod": "module github.com/octocat/linguist\n\ngo 1.22\n\nrequire github.com/spf13/cobra v1.8.0\n",
        ],
    ]

    static func iso(_ daysAgo: Double) -> String {
        Date(timeIntervalSinceNow: -daysAgo * 86_400).formatted(Date.ISO8601FormatStyle(timeZone: .gmt))
    }

    static func response(to request: URLRequest) -> String? {
        guard let url = request.url else { return nil }
        let host = url.host() ?? ""
        let path = url.path()
        switch host {
        case "endoflife.date":
            return endOfLife(product: url.lastPathComponent)
        case "api.osv.dev":
            return osv(path: path, body: request.httpBody)
        case "registry.npmjs.org":
            let latest = ["lodash": "4.17.21", "express": "4.21.2", "left-pad": "1.3.0", "jest": "29.7.0"]
            let name = url.pathComponents.dropFirst().first ?? ""
            return latest[name].map { #"{"version":"\#($0)"}"# }
        case "proxy.golang.org":
            return path.contains("cobra") ? #"{"Version":"v1.8.1"}"# : nil
        default:
            break
        }
        if path == "/search/issues" { return search(query: url.query() ?? "") }
        if path == "/graphql" { return datedTags(body: request.httpBody) }
        let parts = url.pathComponents
        // /repos/octocat/<repo>/...
        guard parts.count >= 5, parts[1] == "repos", parts[2] == FakeGitHub.login else { return nil }
        let repo = parts[3]
        switch parts[4] {
        case "tags":
            let names = tags[repo] ?? []
            return "[" + names.map { #"{"name":"\#($0)"}"# }.joined(separator: ",") + "]"
        case "git":
            let paths = files[repo].map { Array($0.keys).sorted() } ?? []
            return #"{"tree":["# + paths.map { #"{"path":"\#($0)","type":"blob"}"# }.joined(separator: ",") + "]}"
        case "contents":
            let file = parts.dropFirst(5).joined(separator: "/")
            return files[repo]?[file]
        default:
            return nil
        }
    }

    static func search(query: String) -> String {
        let decoded = query.removingPercentEncoding ?? query
        let onlyOpen = decoded.contains("is:open")
        let items = pullRequests.filter { !onlyOpen || $0.state == "open" }.map { pr -> String in
            let closed = pr.state == "open" ? "null" : #""\#(iso(pr.daysAgo - 0.5))""#
            let merged = pr.state == "merged" ? #""\#(iso(pr.daysAgo - 0.5))""# : "null"
            return #"{"number":\#(pr.number),"title":"\#(pr.title)","created_at":"\#(iso(pr.daysAgo))","draft":false,"#
                + #""state":"\#(pr.state == "open" ? "open" : "closed")","closed_at":\#(closed),"pull_request":{"merged_at":\#(merged)},"#
                + #""user":{"login":"\#(pr.author)"},"html_url":"https://github.com/octocat/\#(pr.repo)/pull/\#(pr.number)","#
                + #""repository_url":"https://api.github.com/repos/octocat/\#(pr.repo)"}"#
        }
        return #"{"total_count":\#(items.count),"items":["# + items.joined(separator: ",") + "]}"
    }

    /// De GraphQL-vraag naar tags met datum (`GitHubProvider.datedTags`): de tags van de repo,
    /// de eerste een paar dagen oud en elke volgende een maand ouder.
    static func datedTags(body: Data?) -> String {
        struct Query: Decodable {
            struct Variables: Decodable { let owner: String; let name: String }
            let variables: Variables
        }
        let query = body.flatMap { try? JSONDecoder().decode(Query.self, from: $0) }
        guard let query, query.variables.owner == FakeGitHub.login, let names = tags[query.variables.name] else {
            return #"{"data":{"repository":null}}"#
        }
        let nodes = names.enumerated().map { index, name in
            #"{"name":"\#(name)","target":{"committedDate":"\#(iso(3 + Double(index) * 30))"}}"#
        }
        return #"{"data":{"repository":{"refs":{"nodes":["# + nodes.joined(separator: ",") + "]}}}}"
    }

    static func endOfLife(product: String) -> String? {
        let releases: [(name: String, date: String, eol: Bool, latest: String)]
        switch product {
        case "nodejs":
            releases = [("22", "2024-04-24", false, "22.11.0"), ("20", "2023-04-18", false, "20.18.0"), ("16", "2021-04-20", true, "16.20.2")]
        case "go":
            releases = [("1.23", "2024-08-13", false, "1.23.3"), ("1.22", "2024-02-06", false, "1.22.9")]
        default:
            return nil
        }
        let list = releases.map {
            #"{"name":"\#($0.name)","releaseDate":"\#($0.date)","isEol":\#($0.eol),"latest":{"name":"\#($0.latest)"}}"#
        }
        return #"{"result":{"releases":["# + list.joined(separator: ",") + "]}}"
    }

    static func osv(path: String, body: Data?) -> String? {
        if path == "/v1/querybatch" {
            struct Batch: Decodable {
                struct Query: Decodable {
                    struct Package: Decodable { let name: String }
                    let package: Package
                    let version: String
                }
                let queries: [Query]
            }
            let queries = body.flatMap { try? JSONDecoder().decode(Batch.self, from: $0) }?.queries ?? []
            let results = queries.map { query in
                switch (query.package.name, query.version) {
                case ("lodash", "4.17.20"), ("lodash", "4.17.15"):
                    #"{"vulns":[{"id":"GHSA-35jh-r3h4-6jhm"},{"id":"GHSA-29mw-wpgm-hmr9"}]}"#
                case ("qs", "6.10.1"):
                    #"{"vulns":[{"id":"GHSA-hrpp-h998-j3pp"}]}"#
                case ("semver", "6.3.0"):
                    #"{"vulns":[{"id":"GHSA-c2qf-rxjj-qqgw"}]}"#
                default:
                    "{}"
                }
            }
            return #"{"results":["# + results.joined(separator: ",") + "]}"
        }
        if path.hasSuffix("GHSA-35jh-r3h4-6jhm") {
            return #"{"id":"GHSA-35jh-r3h4-6jhm","aliases":["CVE-2021-23337"],"summary":"Command Injection in lodash","database_specific":{"severity":"HIGH"},"affected":[{"package":{"name":"lodash","ecosystem":"npm"},"ranges":[{"type":"SEMVER","events":[{"introduced":"0"},{"fixed":"4.17.21"}]}]}]}"#
        }
        if path.hasSuffix("GHSA-29mw-wpgm-hmr9") {
            return #"{"id":"GHSA-29mw-wpgm-hmr9","aliases":["CVE-2020-28500"],"summary":"Regular Expression Denial of Service (ReDoS) in lodash","database_specific":{"severity":"MODERATE"},"affected":[{"package":{"name":"lodash","ecosystem":"npm"},"ranges":[{"type":"SEMVER","events":[{"introduced":"4.0.0"},{"fixed":"4.17.21"}]}]}]}"#
        }
        if path.hasSuffix("GHSA-hrpp-h998-j3pp") {
            return #"{"id":"GHSA-hrpp-h998-j3pp","aliases":["CVE-2022-24999"],"summary":"qs vulnerable to Prototype Pollution","database_specific":{"severity":"HIGH"},"affected":[{"package":{"name":"qs","ecosystem":"npm"},"ranges":[{"type":"SEMVER","events":[{"introduced":"6.10.0"},{"fixed":"6.10.3"}]}]}]}"#
        }
        if path.hasSuffix("GHSA-c2qf-rxjj-qqgw") {
            return #"{"id":"GHSA-c2qf-rxjj-qqgw","aliases":["CVE-2022-25883"],"summary":"semver vulnerable to Regular Expression Denial of Service","database_specific":{"severity":"MODERATE"},"affected":[{"package":{"name":"semver","ecosystem":"npm"},"ranges":[{"type":"SEMVER","events":[{"introduced":"6.0.0"},{"fixed":"6.3.1"}]}]}]}"#
        }
        return nil
    }
}
#endif
