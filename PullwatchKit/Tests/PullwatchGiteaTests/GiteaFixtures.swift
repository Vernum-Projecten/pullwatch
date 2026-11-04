import Foundation

/// Antwoorden in de vorm die Codeberg (Forgejo 16) en gitea.com (Gitea) echt gaven, anoniem
/// opgehaald op 4 november 2026 en ingekort tot de velden die ertoe doen plus een paar die
/// Pullwatch moet negeren. `host` maakt dezelfde vorm voor elke smaak.
enum GiteaFixtures {
    static func user(_ login: String = "jdoe", fullName: String = "Jane Doe", host: String = "codeberg.org") -> String {
        #"""
        {"id":179,"login":"\#(login)","login_name":"","source_id":0,"full_name":"\#(fullName)",
         "email":"\#(login)@noreply.\#(host)","avatar_url":"https://\#(host)/avatars/5bf762c71ac84565e8a1773d4fd63744",
         "html_url":"https://\#(host)/\#(login)","language":"","is_admin":false,"visibility":"public","username":"\#(login)"}
        """#
    }

    /// Forgejo noemt `username` naast `name`; Gitea alleen `name`.
    static func organization(_ name: String, forgejo: Bool = true) -> String {
        let username = forgejo ? #","username":"\#(name)""# : ""
        return #"""
        {"id":70422,"name":"\#(name)","full_name":"\#(name.capitalized)","email":"",
         "avatar_url":"https://codeberg.org/avatars/dae8ab126a96f6fbd6942cf08ab92382","description":"Beyond coding. We forge.",
         "website":"","location":"","visibility":"public","repo_admin_change_team_access":true\#(username)}
        """#
    }

    static let orgNotFound = #"""
    {"message":"GetOrgByName","url":"https://codeberg.org/api/swagger","errors":["user redirect does not exist [name: jdoe]"]}
    """#

    static let notFound = #"""
    {"message":"The target couldn't be found.","url":"https://codeberg.org/api/swagger","errors":[]}
    """#

    static let tokenRequired = #"""
    {"message":"token is required","url":"https://codeberg.org/api/swagger"}
    """#

    /// 403 van Forgejo voor een token zonder de scope.
    static func forgejoMissingScope(_ scope: String) -> String {
        #"{"message":"token does not have at least one of required scope(s): [\#(scope)]","url":"https://codeberg.org/api/swagger"}"#
    }

    /// 403 van Gitea voor een token zonder de scope.
    static func giteaMissingScope(_ scope: String) -> String {
        #"{"message":"token does not have at least one of required scope(s), required=[\#(scope)], token scope=read:user","url":"https://gitea.com/api/swagger"}"#
    }

    static func repository(_ fullName: String, archived: Bool = false, host: String = "codeberg.org") -> String {
        let name = fullName.split(separator: "/").last.map(String.init) ?? fullName
        return #"""
        {"id":70845,"name":"\#(name)","full_name":"\#(fullName)","private":false,"fork":false,
         "html_url":"https://\#(host)/\#(fullName)","default_branch":"main","archived":\#(archived),"empty":false}
        """#
    }

    /// Een pull request uit `/repos/issues/search?type=pulls`. Zonder `draft` (nil) zoals een
    /// Gitea van vóór 1.22.
    static func issue(
        number: Int,
        repo: String = "acme/api",
        state: String = "open",
        title: String? = nil,
        draft: Bool? = false,
        merged: Bool = false,
        mergedAt: String? = nil,
        closedAt: String? = nil,
        author: String = "alice",
        fullName: String = "Alice Example",
        host: String = "codeberg.org"
    ) -> String {
        let draftField = draft.map { #","draft":\#($0)"# } ?? ""
        let merged = #""merged":\#(merged),"merged_at":\#(mergedAt.map { "\"\($0)\"" } ?? "null")"#
        let owner = repo.split(separator: "/").first.map(String.init) ?? repo
        return #"""
        {"id":\#(8_000_000 + number),"url":"https://\#(host)/api/v1/repos/\#(repo)/pulls/\#(number)",
         "html_url":"https://\#(host)/\#(repo)/pulls/\#(number)","number":\#(number),
         "user":{"id":141082,"login":"\#(author)","full_name":"\#(fullName)","email":"\#(author)@noreply.\#(host)",
                 "avatar_url":"https://\#(host)/avatars/b25a3a294c6f5514eb9f56b9c808425d","html_url":"https://\#(host)/\#(author)"},
         "title":"\#(title ?? "PR \(number)")","labels":[],"state":"\#(state)","comments":0,
         "created_at":"2026-11-04T11:33:56+01:00","updated_at":"2026-11-04T12:39:40+01:00",
         "closed_at":\#(closedAt.map { "\"\($0)\"" } ?? "null"),
         "pull_request":{\#(merged)\#(draftField),"html_url":"https://\#(host)/\#(repo)/pulls/\#(number)"},
         "repository":{"id":73144,"name":"\#(repo.split(separator: "/").last ?? "")","owner":"\#(owner)","full_name":"\#(repo)"},
         "pin_order":0}
        """#
    }

    /// Een pull request uit `/repos/:eigenaar/:repo/pulls` of `/pulls/:nummer`.
    static func pull(
        number: Int,
        repo: String = "acme/api",
        state: String = "open",
        draft: Bool = false,
        merged: Bool = false,
        sha: String = "158d89a5e3b836a3326e3ffa47df7ed80ca8fc82",
        updatedAt: String = "2026-11-04T12:39:40+01:00",
        host: String = "codeberg.org"
    ) -> String {
        #"""
        {"id":3576777,"url":"https://\#(host)/api/v1/repos/\#(repo)/pulls/\#(number)","number":\#(number),
         "user":{"id":141082,"login":"alice","full_name":"Alice Example","email":"alice@noreply.\#(host)",
                 "avatar_url":"https://\#(host)/avatars/b25a3a294c6f5514eb9f56b9c808425d","html_url":"https://\#(host)/alice"},
         "title":"PR \#(number)","labels":[],"milestone":null,"assignee":null,"assignees":null,"requested_reviewers":[],
         "state":"\#(state)","draft":\#(draft),"is_locked":false,"comments":0,
         "html_url":"https://\#(host)/\#(repo)/pulls/\#(number)","mergeable":false,"merged":\#(merged),
         "merged_at":\#(merged ? "\"2026-11-04T13:00:00+01:00\"" : "null"),"merge_commit_sha":null,
         "base":{"label":"main","ref":"main","sha":"891c02315006e3b8fbb74819626c7cc76acb5260","repo_id":73144,
                 "repo":{"id":73144,"name":"api","full_name":"\#(repo)","html_url":"https://\#(host)/\#(repo)","default_branch":"main"}},
         "head":{"label":"feature","ref":"feature","sha":"\#(sha)","repo_id":73144,
                 "repo":{"id":73144,"name":"api","full_name":"\#(repo)","html_url":"https://\#(host)/\#(repo)","default_branch":"main"}},
         "created_at":"2026-11-04T11:33:56+01:00","updated_at":"\#(updatedAt)",
         "closed_at":\#(state == "closed" ? "\"2026-11-04T13:00:00+01:00\"" : "null"),"pin_order":0,"flow":0}
        """#
    }

    static func tag(_ name: String, created: String = "2026-10-26T15:25:55+01:00", host: String = "codeberg.org") -> String {
        #"""
        {"name":"\#(name)","message":"Release","id":"363f3dc30beef902b187af5a5244ff7af44901e6",
         "commit":{"url":"https://\#(host)/api/v1/repos/acme/api/git/commits/363f3dc3","sha":"363f3dc30beef902b187af5a5244ff7af44901e6",
                   "created":"\#(created)"},
         "zipball_url":"https://\#(host)/acme/api/archive/\#(name).zip","tarball_url":"https://\#(host)/acme/api/archive/\#(name).tar.gz"}
        """#
    }

    static func release(_ tag: String, prerelease: Bool = false, draft: Bool = false, author: String = "jdoe", host: String = "codeberg.org") -> String {
        #"""
        {"id":13216583,"tag_name":"\#(tag)","target_commitish":"","name":"Version \#(tag)","body":"Notes",
         "url":"https://\#(host)/api/v1/repos/acme/api/releases/13216583","html_url":"https://\#(host)/acme/api/releases/tag/\#(tag)",
         "draft":\#(draft),"prerelease":\#(prerelease),"created_at":"2026-10-26T19:39:32+01:00","published_at":"2026-10-26T19:39:32+01:00",
         "author":{"id":70541,"login":"\#(author)","full_name":"","email":"\#(author)@noreply.\#(host)",
                   "avatar_url":"https://\#(host)/avatars/83623afe083e82955f79b2dfeea58bd9","html_url":"https://\#(host)/\#(author)"},
         "assets":[]}
        """#
    }

    /// De gecombineerde stand met één status per gegeven stand.
    static func combinedStatus(_ states: [String]) -> String {
        let statuses = states.enumerated().map { index, state in
            #"{"id":\#(index + 1),"status":"\#(state)","target_url":"/acme/api/actions/runs/1/jobs/\#(index)","description":"","url":"https://codeberg.org/api/v1/repos/acme/api/statuses/158d89a5","context":"ci / job \#(index)","creator":null,"created_at":"2026-11-04T12:39:47+01:00","updated_at":"2026-11-04T12:39:47+01:00"}"#
        }
        return #"""
        {"state":"success","sha":"158d89a5e3b836a3326e3ffa47df7ed80ca8fc82","total_count":\#(states.count),
         "statuses":[\#(statuses.joined(separator: ","))],"repository":{"id":73144,"full_name":"acme/api"},"commit_url":"","url":""}
        """#
    }

    static func commit(name: String, email: String, login: String?, message: String) -> String {
        let author = login.map {
            #"{"id":141082,"login":"\#($0)","full_name":"","email":"\#($0)@noreply.codeberg.org","avatar_url":"https://codeberg.org/avatars/\#($0)","html_url":"https://codeberg.org/\#($0)"}"#
        } ?? "null"
        return #"""
        {"url":"https://codeberg.org/api/v1/repos/acme/api/git/commits/158d89a5","sha":"158d89a5","created":"2026-11-04T11:39:32Z",
         "html_url":"https://codeberg.org/acme/api/commit/158d89a5",
         "commit":{"url":"https://codeberg.org/api/v1/repos/acme/api/git/commits/158d89a5",
                   "author":{"name":"\#(name)","email":"\#(email)","date":"2026-11-04T11:39:32Z"},
                   "committer":{"name":"\#(name)","email":"\#(email)","date":"2026-11-04T11:39:32Z"},
                   "message":"\#(message)","verification":null},
         "author":\#(author),"committer":\#(author),"parents":[],"files":null,"stats":{"total":4,"additions":2,"deletions":2}}
        """#
    }

    /// Een pagina van de boom; `truncated` staat bij pagineren altijd aan.
    static func tree(_ entries: [(path: String, type: String)], page: Int, total: Int) -> String {
        let items = entries.map {
            #"{"path":"\#($0.path)","mode":"100644","type":"\#($0.type)","size":828,"sha":"65872e73","url":"https://codeberg.org/api/v1/repos/acme/api/git/blobs/65872e73"}"#
        }
        return #"""
        {"sha":"4c9fb58a0f8e1bfadbac28e515fbe20b158aca38","url":"https://codeberg.org/api/v1/repos/acme/api/git/trees/4c9fb58a",
         "tree":[\#(items.joined(separator: ","))],"truncated":true,"page":\#(page),"total_count":\#(total)}
        """#
    }
}
