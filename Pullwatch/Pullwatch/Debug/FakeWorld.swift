#if DEBUG
import Foundation
import PullwatchCore
import Synchronization

/// De nagespeelde inhoud achter `-PullwatchFakeData`: drie repo's van octocat met PR's van
/// een paar auteurs, tags, en bestanden waarin een oude Node, een package met een nieuwe versie
/// en een bekende kwetsbaarheid zitten. GitHubs adviezen hebben CVSS en CWE's; hello-world heeft
/// open meldingen van code scanning, linguist een eigen advies, en secret scanning mag de app
/// nergens lezen (zoals bij de test-app zonder dat recht).
nonisolated enum FakeWorld {
    struct PR {
        let repo: String
        let number: Int
        let title: String
        let author: String
        let daysAgo: Double
        /// "open", "merged" of "closed".
        let state: String
        /// Een draft: open drafts zijn grijs in de lijst en de statistieken, zoals op GitHub.
        var isDraft = false
    }

    // Alle vijf de statussen komen voor (open, draft, in de merge queue, gemerged, gesloten zonder
    // merge), zodat de lijsten en statistieken in de rondleiding ze allemaal tonen. Welke PR in de
    // rij staat zegt `mergeQueue`.
    static let pullRequests: [PR] = [
        PR(repo: "hello-world", number: 42, title: "Try a dark theme for the page", author: "jdoe", daysAgo: 3, state: "open", isDraft: true),
        PR(repo: "hello-world", number: 41, title: "Bump lodash to 4.17.21", author: "dependabot[bot]", daysAgo: 0.2, state: "open"),
        PR(repo: "hello-world", number: 40, title: "Add a greeting in Dutch", author: "mona", daysAgo: 1, state: "open"),
        PR(repo: "hello-world", number: 38, title: "Move the build to Node 22", author: "hubot", daysAgo: 4, state: "merged"),
        PR(repo: "hello-world", number: 35, title: "Fix the README links", author: "mona", daysAgo: 12, state: "merged"),
        PR(repo: "hello-world", number: 31, title: "Experiment with a second greeting", author: "jdoe", daysAgo: 40, state: "closed"),
        PR(repo: "spoon-knife", number: 22, title: "Update express to the latest 4.x release", author: "hubot", daysAgo: 0.5, state: "open"),
        PR(repo: "spoon-knife", number: 20, title: "Replace the fork icon", author: "amelie", daysAgo: 2, state: "closed"),
        PR(repo: "spoon-knife", number: 21, title: "Add a fork button to the page", author: "jdoe", daysAgo: 6, state: "merged"),
        PR(repo: "spoon-knife", number: 19, title: "Clean up the stylesheet", author: "mona", daysAgo: 33, state: "merged"),
        PR(repo: "spoon-knife", number: 17, title: "Translate the page into French", author: "amelie", daysAgo: 70, state: "merged"),
        PR(repo: "linguist", number: 13, title: "Recognise Gleam files", author: "mona", daysAgo: 1.5, state: "open", isDraft: true),
        PR(repo: "linguist", number: 12, title: "Recognise Swift macros as Swift", author: "amelie", daysAgo: 2, state: "open"),
        PR(repo: "linguist", number: 11, title: "Speed up the language detection", author: "hubot", daysAgo: 20, state: "merged"),
        PR(repo: "linguist", number: 10, title: "Rewrite the tokenizer in Rust", author: "hubot", daysAgo: 45, state: "closed"),
        PR(repo: "linguist", number: 9, title: "Drop support for Go 1.20", author: "jdoe", daysAgo: 95, state: "merged"),
        PR(repo: "linguist", number: 7, title: "Add a heuristic for .h files", author: "mona", daysAgo: 150, state: "merged"),
    ]

    /// Wie er per PR ("repo#nummer") meewerkte: login (nil = alleen een naam uit een trailer) en naam.
    static let coAuthors: [String: [(login: String?, name: String)]] = [
        "hello-world#40": [("amelie", "Amélie Laurent"), ("jdoe", "John Doe")],
        "hello-world#38": [("mona", "Mona Lisa")],
        "spoon-knife#21": [("amelie", "Amélie Laurent"), ("mona", "Mona Lisa"), (nil, "Jan de Vries")],
        "linguist#12": [(nil, "Jan de Vries")],
    ]

    /// Een tag: geannoteerd (met een tagger) of licht (alleen de auteur van de commit; zonder
    /// login een naam uit git), met of zonder release.
    struct FakeTag {
        struct Release {
            let title: String
            let author: String
            var isPrerelease = false
        }

        let name: String
        let daysAgo: Double
        /// GitHub-login van de tagger; nil voor een lichte tag.
        var tagger: String?
        /// Auteur van de commit: een login of, met `committerLogin` uit, een naam uit git.
        var committer = "mona"
        var committerLogin = true
        var release: Release?
    }

    static let tags: [String: [FakeTag]] = [
        "hello-world": [
            FakeTag(name: "v1.3.0-beta.1", daysAgo: 0.3, tagger: "hubot",
                    release: .init(title: "Greetings in five languages (beta)", author: "hubot", isPrerelease: true)),
            FakeTag(name: "v1.2.0", daysAgo: 3, tagger: "mona", release: .init(title: "Dutch greeting", author: "github-actions[bot]")),
            FakeTag(name: "v1.1.0", daysAgo: 33, committer: "jdoe"),
        ],
        "spoon-knife": [
            FakeTag(name: "v3.0.1", daysAgo: 5, tagger: "jdoe", release: .init(title: "Fork button", author: "jdoe")),
        ],
        "linguist": [
            FakeTag(name: "v9.4.0", daysAgo: 1.5, tagger: "amelie"),
            FakeTag(name: "v9.3.2", daysAgo: 40, committer: "Jan de Vries", committerLogin: false),
        ],
    ]

    static let files: [String: [String: String]] = [
        // Een monorepo op Node 16: de root en packages/web, lodash direct (4.17.20, binnen bereik bij
        // te werken), via express en body-parser (4.17.15, vastgehouden door body-parser) en in
        // packages/web (4.17.21), een kwetsbare qs alleen transitief en een dev-only lek. express 5
        // en vite 5 vragen een nieuwere Node; in packages/web houdt react-dom 18 react 19 tegen, en
        // react-dom 19 vraagt react 19 als peer.
        "hello-world": [
            ".nvmrc": "16\n",
            "package.json": #"{"name":"hello-world","workspaces":["packages/*"],"dependencies":{"lodash":"^4.17.20","express":"^4.18.0"},"devDependencies":{"jest":"^29.7.0","vite":"^4.5.0"}}"#,
            "packages/web/package.json": #"{"name":"web","dependencies":{"lodash":"4.17.21","left-pad":"1.3.0","react":"^18.3.1","react-dom":"^18.3.1"}}"#,
            "package-lock.json": #"{"lockfileVersion":3,"packages":{"#
                + #""":{"name":"hello-world","workspaces":["packages/*"],"dependencies":{"lodash":"^4.17.20","express":"^4.18.0"},"devDependencies":{"jest":"^29.7.0","vite":"^4.5.0"}},"#
                + #""packages/web":{"name":"web","dependencies":{"lodash":"4.17.21","left-pad":"1.3.0","react":"^18.3.1","react-dom":"^18.3.1"}},"#
                + #""node_modules/web":{"resolved":"packages/web","link":true},"#
                + #""node_modules/lodash":{"version":"4.17.20"},"#
                + #""node_modules/express":{"version":"4.18.0","dependencies":{"body-parser":"1.20.1"}},"#
                + #""node_modules/body-parser":{"version":"1.20.1","dependencies":{"qs":"6.10.1","lodash":"4.17.15"}},"#
                + #""node_modules/body-parser/node_modules/lodash":{"version":"4.17.15"},"#
                + #""node_modules/qs":{"version":"6.10.1"},"#
                + #""node_modules/jest":{"version":"29.7.0","dev":true,"dependencies":{"semver":"^6.3.0"}},"#
                + #""node_modules/semver":{"version":"6.3.0","dev":true},"#
                + #""node_modules/vite":{"version":"4.5.0","dev":true,"engines":{"node":"^14.18.0 || >=16.0.0"}},"#
                + #""node_modules/left-pad":{"version":"1.3.0"},"#
                + #""packages/web/node_modules/lodash":{"version":"4.17.21"},"#
                + #""packages/web/node_modules/react":{"version":"18.3.1"},"#
                + #""packages/web/node_modules/react-dom":{"version":"18.3.1","peerDependencies":{"react":"^18.3.1"}}}}"#,
        ],
        // lodash alleen via express: in Afhankelijkheden "alleen transitief".
        "spoon-knife": [
            ".nvmrc": "22\n",
            "package.json": #"{"name":"spoon-knife","dependencies":{"express":"^4.18.0","left-pad":"1.3.0"}}"#,
            "package-lock.json": #"{"lockfileVersion":3,"packages":{"":{"dependencies":{"express":"^4.18.0","left-pad":"1.3.0"}},"node_modules/express":{"version":"4.18.0","dependencies":{"lodash":"4.17.21"}},"node_modules/lodash":{"version":"4.17.21"},"node_modules/left-pad":{"version":"1.3.0"}}}"#,
        ],
        "linguist": [
            "go.mod": "module github.com/octocat/linguist\n\ngo 1.22\n\nrequire github.com/spf13/cobra v1.8.0\n",
        ],
    ]

    /// Het verkorte packument per npm-package (`dist-tags`, per versie dependencies, peers en
    /// engines), zodat Afhankelijkheden elke status laat zien: binnen bereik (lodash), major met
    /// manifest (express in spoon-knife), vastgehouden door een ouder (react door react-dom, qs
    /// en lodash door body-parser), door een peer (react-dom) en door de runtime (vite, express op Node 16).
    static let npmPackuments: [String: String] = {
        func packument(_ latest: String, _ versions: [(String, String)]) -> String {
            let entries = versions.map { #""\#($0.0)":{\#($0.1)}"# }.joined(separator: ",")
            return #"{"dist-tags":{"latest":"\#(latest)"},"versions":{\#(entries)}}"#
        }
        return [
            "lodash": packument("4.17.21", [("4.17.15", ""), ("4.17.20", ""), ("4.17.21", "")]),
            "express": packument("5.1.0", [
                ("4.18.0", #""dependencies":{"body-parser":"1.20.1"},"engines":{"node":">= 0.10.0"}"#),
                ("4.21.2", #""dependencies":{"body-parser":"1.20.3"},"engines":{"node":">= 0.10.0"}"#),
                ("5.1.0", #""dependencies":{"body-parser":"^2.2.0"},"engines":{"node":">= 18"}"#),
            ]),
            "body-parser": packument("2.2.0", [
                ("1.20.1", #""dependencies":{"qs":"6.10.1","lodash":"4.17.15"}"#),
                ("1.20.2", #""dependencies":{"qs":"^6.10.3"}"#),
                ("1.20.3", #""dependencies":{"qs":"^6.13.0"}"#),
                ("2.2.0", #""dependencies":{"qs":"^6.14.0"},"engines":{"node":">=18"}"#),
            ]),
            "qs": packument("6.14.0", [("6.10.1", ""), ("6.10.3", ""), ("6.11.0", ""), ("6.13.0", ""), ("6.14.0", "")]),
            "left-pad": packument("1.3.0", [("1.3.0", "")]),
            "jest": packument("29.7.0", [("29.7.0", #""dependencies":{"semver":"^6.3.0"}"#)]),
            "semver": packument("7.6.3", [("6.3.0", ""), ("6.3.1", ""), ("7.6.3", "")]),
            "vite": packument("6.0.0", [
                ("4.5.0", #""engines":{"node":"^14.18.0 || >=16.0.0"}"#),
                ("4.5.5", #""engines":{"node":"^14.18.0 || >=16.0.0"}"#),
                ("5.4.0", #""engines":{"node":"^18.0.0 || >=20.0.0"}"#),
                ("6.0.0", #""engines":{"node":"^18.0.0 || ^20.0.0 || >=22.0.0"}"#),
            ]),
            "react": packument("19.1.0", [("18.3.1", ""), ("19.0.0", ""), ("19.1.0", "")]),
            "react-dom": packument("19.1.0", [
                ("18.3.1", #""peerDependencies":{"react":"^18.3.1"}"#),
                ("19.0.0", #""peerDependencies":{"react":"^19.0.0"}"#),
                ("19.1.0", #""peerDependencies":{"react":"^19.1.0"}"#),
            ]),
        ]
    }()

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
            let name = url.pathComponents.dropFirst().first ?? ""
            return npmPackuments[name]
        case "proxy.golang.org":
            guard path.contains("cobra") else { return nil }
            if path.hasSuffix(".mod") { return "module github.com/spf13/cobra\n\ngo 1.15\n" }
            if path.hasSuffix("/@v/list") { return "v1.8.0\nv1.8.1\n" }
            return #"{"Version":"v1.8.1"}"#
        default:
            break
        }
        if path == "/search/issues" { return search(query: url.query() ?? "") }
        if path.hasPrefix("/advisories/") { return advisory(ghsaId: url.lastPathComponent) }
        if path == "/graphql" {
            let isCoAuthorQuery = request.httpBody.map { String(decoding: $0, as: UTF8.self).contains("pullRequest(number") } ?? false
            return isCoAuthorQuery ? coAuthorCommits(body: request.httpBody) : tagsAndReleases(body: request.httpBody)
        }
        let parts = url.pathComponents
        if let extra = extraRepoResponse(parts) { return extra }
        // /repos/octocat/<repo>/...
        guard parts.count >= 5, parts[1] == "repos", parts[2] == FakeGitHub.login else { return nil }
        let repo = parts[3]
        switch parts[4] {
        case "git":
            let paths = files[repo].map { Array($0.keys).sorted() } ?? []
            return #"{"tree":["# + paths.map { #"{"path":"\#($0)","type":"blob"}"# }.joined(separator: ",") + "]}"
        case "contents":
            let file = parts.dropFirst(5).joined(separator: "/")
            return files[repo]?[file]
        case "code-scanning":
            return repo == "hello-world" ? codeScanningAlerts : #"{"message":"no analysis found"}"#
        case "secret-scanning":
            return #"{"message":"Resource not accessible by integration"}"#
        case "security-advisories":
            return repo == "linguist" ? ownAdvisories : "[]"
        default:
            return nil
        }
    }

    /// Een losse repo van een andere organisatie, voor "Andere repositories": openbaar, maar de
    /// GitHub App is er niet geïnstalleerd. Met token geeft GitHub hier 404 (zie `status(of:)`),
    /// zonder token wel antwoord, zoals bij de echte openEHR/specifications-AM.
    static let extraOwner = "openEHR"
    static let extraRepo = "specifications-AM"

    static let extraPullRequests: [PR] = [
        PR(repo: extraRepo, number: 50, title: "Clarify the rules for archetype slots", author: "wolandscat", daysAgo: 3, state: "open"),
        PR(repo: extraRepo, number: 48, title: "Fix typos in the ADL 2 grammar", author: "pieterbos", daysAgo: 25, state: "merged"),
    ]

    private static func extraRepoResponse(_ parts: [String]) -> String? {
        guard parts.count >= 4, parts[1] == "repos", parts[2] == extraOwner, parts[3] == extraRepo else { return nil }
        guard parts.count >= 5 else { return #"{"full_name":"\#(extraOwner)/\#(extraRepo)","private":false}"# }
        switch parts[4] {
        case "tags":
            return #"[{"name":"Release-2.3.0"},{"name":"Release-2.2.0"}]"#
        case "releases":
            return #"[{"id":147607295,"tag_name":"Release-2.3.0","name":"AM Release 2.3.0","draft":false,"prerelease":false,"#
                + #""published_at":"\#(iso(9))","html_url":"https://github.com/\#(extraOwner)/\#(extraRepo)/releases/tag/Release-2.3.0","#
                + #""author":{"login":"wolandscat","avatar_url":"https://github.com/wolandscat.png?size=40"}}]"#
        case "git":
            return #"{"tree":[{"path":"README.md","type":"blob"}]}"#
        default:
            return nil
        }
    }

    /// 403 voor secret scanning (geen recht), 404 voor code scanning zonder analyse; de rest 200.
    /// De losse repo van openEHR geeft met token 404 (app niet geïnstalleerd), zonder token 200.
    static func status(of request: URLRequest) -> Int {
        let parts = request.url?.pathComponents ?? []
        if parts.count >= 4, parts[1] == "repos", parts[2] == extraOwner {
            return request.value(forHTTPHeaderField: "Authorization") == nil ? 200 : 404
        }
        guard parts.count >= 5, parts[1] == "repos" else { return 200 }
        switch parts[4] {
        case "secret-scanning": return 403
        case "code-scanning": return parts[3] == "hello-world" ? 200 : 404
        default: return 200
        }
    }

    static let codeScanningAlerts = #"""
        [{"number":7,"created_at":"2026-10-20T09:00:00Z","state":"open","html_url":"https://github.com/octocat/hello-world/security/code-scanning/7",
          "rule":{"id":"js/sql-injection","severity":"error","security_severity_level":"critical","description":"Database query built from user-controlled sources"},
          "tool":{"name":"CodeQL"},"most_recent_instance":{"location":{"path":"src/db.js","start_line":42}}},
         {"number":5,"created_at":"2026-09-02T09:00:00Z","state":"open","html_url":"https://github.com/octocat/hello-world/security/code-scanning/5",
          "rule":{"id":"js/reflected-xss","severity":"error","security_severity_level":"high","description":"Reflected cross-site scripting"},
          "tool":{"name":"CodeQL"},"most_recent_instance":{"location":{"path":"src/greet.js","start_line":17}}},
         {"number":3,"created_at":"2026-06-11T09:00:00Z","state":"open","html_url":"https://github.com/octocat/hello-world/security/code-scanning/3",
          "rule":{"id":"js/unused-local-variable","severity":"note","security_severity_level":null,"description":"Unused variable, import, function or class"},
          "tool":{"name":"CodeQL"},"most_recent_instance":{"location":{"path":"src/index.js","start_line":3}}}]
        """#

    static let ownAdvisories = #"""
        [{"ghsa_id":"GHSA-4q2v-9x7c-m3hp","cve_id":"CVE-2026-31337","html_url":"https://github.com/octocat/linguist/security/advisories/GHSA-4q2v-9x7c-m3hp",
          "summary":"Unbounded recursion in the heuristics for .h files","severity":"medium","state":"published","published_at":"2026-08-14T12:00:00Z",
          "vulnerabilities":[{"package":{"ecosystem":"go","name":"github.com/octocat/linguist"},"vulnerable_version_range":"< 9.3.2","patched_versions":"9.3.2"}],
          "cvss_severities":{"cvss_v3":{"vector_string":"CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:L","score":5.3},"cvss_v4":null},
          "cwes":[{"cwe_id":"CWE-674","name":"Uncontrolled Recursion"}]}]
        """#

    /// `GET /advisories/{ghsa_id}`: GitHubs ernst, CVSS en CWE's bij de kwetsbaarheden van OSV.
    static func advisory(ghsaId: String) -> String? {
        let known: [String: (cve: String, severity: String, score: Double, vector: String, cwe: String, name: String)] = [
            "GHSA-35jh-r3h4-6jhm": ("CVE-2021-23337", "high", 7.2, "CVSS:3.1/AV:N/AC:L/PR:H/UI:N/S:U/C:H/I:H/A:H", "CWE-94", "Improper Control of Generation of Code"),
            "GHSA-29mw-wpgm-hmr9": ("CVE-2020-28500", "medium", 5.3, "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:L", "CWE-1333", "Inefficient Regular Expression Complexity"),
            "GHSA-hrpp-h998-j3pp": ("CVE-2022-24999", "high", 7.5, "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H", "CWE-1321", "Improperly Controlled Modification of Object Prototype Attributes"),
            "GHSA-c2qf-rxjj-qqgw": ("CVE-2022-25883", "medium", 5.3, "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:L", "CWE-1333", "Inefficient Regular Expression Complexity"),
        ]
        guard let item = known[ghsaId] else { return nil }
        return #"{"ghsa_id":"\#(ghsaId)","cve_id":"\#(item.cve)","html_url":"https://github.com/advisories/\#(ghsaId)","type":"reviewed","#
            + #""severity":"\#(item.severity)","cvss_severities":{"cvss_v3":{"vector_string":"\#(item.vector)","score":\#(item.score)},"cvss_v4":null},"#
            + #""cwes":[{"cwe_id":"\#(item.cwe)","name":"\#(item.name)"}]}"#
    }

    static func search(query: String) -> String {
        let decoded = query.removingPercentEncoding ?? query
        let onlyOpen = decoded.contains("is:open")
        // De losse repo van openEHR heeft een eigen zoekopdracht (`repo:`); de rest is van octocat.
        let isExtra = decoded.contains("repo:\(extraOwner)/\(extraRepo)")
        let owner = isExtra ? extraOwner : FakeGitHub.login
        let items = (isExtra ? extraPullRequests : pullRequests).filter { !onlyOpen || $0.state == "open" }.map { pr -> String in
            let closed = pr.state == "open" ? "null" : #""\#(iso(pr.daysAgo - 0.5))""#
            let merged = pr.state == "merged" ? #""\#(iso(pr.daysAgo - 0.5))""# : "null"
            // Zoals GitHub: een bot (GitHub App) heeft zijn foto onder `/in/<app-id>`, iemand anders onder
            // `/u/<id>`; hier de openbare `/<login>.png`, die voor een gebruiker hetzelfde toont.
            let avatar = pr.author == "dependabot[bot]"
                ? "https://avatars.githubusercontent.com/in/29110?v=4" : "https://github.com/\(pr.author).png?size=40"
            return #"{"number":\#(pr.number),"title":"\#(pr.title)","created_at":"\#(iso(pr.daysAgo))","updated_at":"\#(iso(pr.daysAgo))","draft":\#(pr.isDraft),"#
                + #""state":"\#(pr.state == "open" ? "open" : "closed")","closed_at":\#(closed),"pull_request":{"merged_at":\#(merged)},"#
                + #""user":{"login":"\#(pr.author)","avatar_url":"\#(avatar)"},"html_url":"https://github.com/\#(owner)/\#(pr.repo)/pull/\#(pr.number)","#
                + #""repository_url":"https://api.github.com/repos/\#(owner)/\#(pr.repo)"}"#
        }
        return #"{"total_count":\#(items.count),"items":["# + items.joined(separator: ",") + "]}"
    }

    /// De GraphQL-vraag naar tags en releases (`GitHubProvider.tags`): per alias (`r0`, `r1`, …)
    /// de tags van die repo met hun tagger of commit-auteur, en de releases. Alleen repo's van
    /// octocat bestaan; de rest is `null`, zoals bij GitHub.
    static func tagsAndReleases(body: Data?) -> String {
        struct Query: Decodable { let variables: [String: String] }
        let variables = body.flatMap { try? JSONDecoder().decode(Query.self, from: $0) }?.variables ?? [:]
        func actor(_ login: String?, name: String) -> String {
            let user = login.map { #"{"login":"\#($0)","avatarUrl":"https://github.com/\#($0).png?size=40"}"# } ?? "null"
            return #"{"name":"\#(name)","avatarUrl":null,"user":\#(user)}"#
        }
        var fields: [String] = []
        for index in 0... {
            guard let owner = variables["o\(index)"], let name = variables["n\(index)"] else { break }
            guard owner == FakeGitHub.login, let list = tags[name] else {
                fields.append(#""r\#(index)":null"#)
                continue
            }
            let refs = list.map { tag -> String in
                let author = actor(tag.committerLogin ? tag.committer : nil, name: tag.committer)
                let commit = #"{"committedDate":"\#(iso(tag.daysAgo + 0.1))","author":\#(author)}"#
                guard let tagger = tag.tagger else { return #"{"name":"\#(tag.name)","target":\#(commit)}"# }
                let taggerJSON = #"{"name":"\#(tagger)","avatarUrl":null,"date":"\#(iso(tag.daysAgo))","#
                    + #""user":{"login":"\#(tagger)","avatarUrl":"https://github.com/\#(tagger).png?size=40"}}"#
                return #"{"name":"\#(tag.name)","target":{"tagger":\#(taggerJSON),"target":\#(commit)}}"#
            }
            let releases = list.compactMap { tag -> String? in
                guard let release = tag.release else { return nil }
                return #"{"id":"RE_\#(name)_\#(tag.name)","tagName":"\#(tag.name)","name":"\#(release.title)","isDraft":false,"#
                    + #""isPrerelease":\#(release.isPrerelease),"publishedAt":"\#(iso(tag.daysAgo))","updatedAt":"\#(iso(tag.daysAgo))","#
                    + #""url":"https://github.com/octocat/\#(name)/releases/tag/\#(tag.name)","#
                    + #""author":{"login":"\#(release.author)","avatarUrl":"https://github.com/\#(release.author).png?size=40"}}"#
            }
            fields.append(#""r\#(index)":{"refs":{"totalCount":\#(refs.count),"nodes":["# + refs.joined(separator: ",") + "]},"
                + #""releases":{"totalCount":\#(releases.count),"nodes":["# + releases.joined(separator: ",") + "]}}")
        }
        return #"{"data":{"# + fields.joined(separator: ",") + "}}"
    }

    /// De checks van de open PR's ("repo#nummer"): geslaagd, overgeslagen, mislukt en bezig, zodat
    /// de lijsten elke stand tonen. De PR's van linguist geven geen checks: daar mist de app het
    /// recht, zoals bij de test-app zonder Checks en Commit statuses.
    static let checks: [String: (passed: Int, skipped: Int, failed: Int, pending: Int)] = [
        "hello-world#42": (3, 0, 0, 0),
        "hello-world#41": (4, 0, 1, 3),
        "hello-world#40": (7, 1, 0, 0),
        "spoon-knife#22": (3, 0, 0, 5),
    ]
    static let checksForbiddenRepo = "linguist"

    /// De open PR's ("repo#nummer") in de merge queue, met hun plek (vanaf 1, zoals GitHub).
    static let mergeQueue: [String: Int] = [
        "hello-world#40": 1,
    ]

    /// De GraphQL-vraag naar commit-auteurs, checks en de merge queue (`GitHubProvider.details`
    /// en `withMergeQueues`): per alias de auteur van de PR en zijn co-auteurs uit `coAuthors`, de
    /// telling uit `checks` en de plek uit `mergeQueue`.
    static func coAuthorCommits(body: Data?) -> String {
        struct Query: Decodable {
            enum Value: Decodable {
                case text(String), number(Int)

                init(from decoder: any Decoder) throws {
                    let c = try decoder.singleValueContainer()
                    if let number = try? c.decode(Int.self) { self = .number(number) } else { self = .text(try c.decode(String.self)) }
                }
            }
            let query: String
            let variables: [String: Value]
        }
        let decoded = body.flatMap { try? JSONDecoder().decode(Query.self, from: $0) }
        let variables = decoded?.variables ?? [:]
        let query = decoded?.query ?? ""
        var fields: [String] = []
        var errors: [String] = []
        for index in 0... {
            guard case .text(let repo) = variables["n\(index)"], case .number(let number) = variables["p\(index)"] else { break }
            let author = pullRequests.first { $0.repo == repo && $0.number == number }?.author ?? FakeGitHub.login
            let people: [(login: String?, name: String)] = [(author, author)] + (coAuthors["\(repo)#\(number)"] ?? [])
            let nodes = people.map { person in
                let user = person.login.map { #"{"login":"\#($0)","avatarUrl":"https://github.com/\#($0).png?size=40"}"# } ?? "null"
                let email = (person.login ?? person.name.lowercased().replacingOccurrences(of: " ", with: ".")) + "@example.com"
                return #"{"name":"\#(person.name)","email":"\#(email)","user":\#(user)}"#
            }
            // Wat deze alias vraagt: de tekst tussen "pr<n>:" en de volgende alias.
            let start = query.range(of: "pr\(index):")?.upperBound ?? query.endIndex
            let end = query.range(of: "pr\(index + 1):", range: start..<query.endIndex)?.lowerBound ?? query.endIndex
            let asked = query[start..<end]
            var parts: [String] = []
            if asked.contains("commits(last: 50)") {
                parts.append(#""commits":{"nodes":[{"commit":{"authors":{"nodes":["# + nodes.joined(separator: ",") + "]}}}]}")
            }
            if asked.contains("headCommit") {
                parts.append(headCommit(repo: repo, number: number))
                if repo == checksForbiddenRepo {
                    errors.append(#"{"type":"FORBIDDEN","path":["pr\#(index)","pullRequest","headCommit","nodes",0,"commit","statusCheckRollup"],"#
                        + #""message":"Resource not accessible by integration"}"#)
                }
            }
            if asked.contains("isInMergeQueue") {
                if let position = mergeQueue["\(repo)#\(number)"] {
                    parts.append(#""isInMergeQueue":true,"mergeQueueEntry":{"state":"AWAITING_CHECKS","position":\#(position),"#
                        + #""enqueuedAt":"\#(iso(0.05))"}"#)
                } else {
                    parts.append(#""isInMergeQueue":false,"mergeQueueEntry":null"#)
                }
            }
            fields.append(#""pr\#(index)":{"pullRequest":{"# + parts.joined(separator: ",") + "}}")
        }
        let errorList = errors.isEmpty ? "" : #","errors":["# + errors.joined(separator: ",") + "]"
        return #"{"data":{"# + fields.joined(separator: ",") + "}" + errorList + "}"
    }

    /// De laatste commit van een PR met de telling van zijn checks; zonder checks (of zonder
    /// recht) `null`, zoals GitHub.
    private static func headCommit(repo: String, number: Int) -> String {
        guard repo != checksForbiddenRepo, let c = checks["\(repo)#\(number)"] else {
            return #""headCommit":{"nodes":[{"commit":{"statusCheckRollup":null}}]}"#
        }
        let runs = [("SUCCESS", c.passed), ("SKIPPED", c.skipped), ("FAILURE", c.failed), ("IN_PROGRESS", c.pending)]
            .filter { $0.1 > 0 }
            .map { #"{"state":"\#($0.0)","count":\#($0.1)}"# }
            .joined(separator: ",")
        return #""headCommit":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"#
            + #""checkRunCountsByState":[\#(runs)],"statusContextCountsByState":[]}}}}]}"#
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
            return #"{"id":"GHSA-29mw-wpgm-hmr9","aliases":["CVE-2020-28500"],"summary":"Regular Expression Denial of Service (ReDoS) in lodash","published":"2022-01-06T20:30:46Z","modified":"2025-09-29T21:12:31Z","severity":[{"type":"CVSS_V3","score":"CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:L"}],"references":[{"type":"ADVISORY","url":"https://nvd.nist.gov/vuln/detail/CVE-2020-28500"},{"type":"FIX","url":"https://github.com/lodash/lodash/commit/c4847ebe7d14540bb28a8b932a9ce1b9ecbfee1a"}],"database_specific":{"severity":"MODERATE"},"affected":[{"package":{"name":"lodash","ecosystem":"npm"},"ranges":[{"type":"SEMVER","events":[{"introduced":"4.0.0"},{"fixed":"4.17.21"}]}]}]}"#
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
