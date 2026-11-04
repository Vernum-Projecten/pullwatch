import Foundation

/// Antwoorden in de vorm die Bitbucket Cloud (REST API 2.0) echt geeft, ingekort uit anonieme
/// antwoorden van openbare repo's van de workspace `atlassian` (november 2026) tot de velden die
/// ertoe doen plus een paar die Pullwatch moet negeren. `/user` en de 403 van een ontbrekende
/// scope kunnen niet anoniem; die volgen het schema `account` en de vorm van de foutmeldingen
/// (`{"type": "error", "error": {…}}`) uit de OpenAPI-beschrijving van Atlassian.
enum BitbucketFixtures {
    static let user = #"""
    {"display_name":"Jane Doe","links":{"avatar":{"href":"https://secure.gravatar.com/avatar/1?d=https%3A%2F%2Favatar-management--avatars.us-west-2.prod.public.atl-paas.net%2Finitials%2FJD-3.png"}},
     "type":"user","uuid":"{11111111-2222-3333-4444-555555555555}","account_id":"557057:abc","nickname":"jdoe",
     "created_on":"2020-01-02T10:00:00.000000+00:00","is_staff":false,"account_status":"active"}
    """#

    static let unknownWorkspace = #"""
    {"type": "error", "error": {"message": "No workspace with identifier 'nobody'."}}
    """#

    static let noAccess = #"""
    {"type": "error", "error": {"message": "You may not have access to this repository or it no longer exists in this workspace. If you think this repository exists and you have access, make sure you are authenticated."}}
    """#

    static let missingScope = #"""
    {"type": "error", "error": {"message": "Your credentials lack one or more required privilege scopes.", "detail": {"granted": ["read:user:bitbucket"], "required": ["read:repository:bitbucket"]}}}
    """#

    static func repositories(_ names: [(String, String)], next: String? = nil) -> String {
        let values = names.map { #"{"full_name": "\#($0.0)", "updated_on": "\#($0.1)"}"# }.joined(separator: ", ")
        return #"{"values": [\#(values)]\#(next.map { #", "next": "\#($0)""# } ?? "")}"#
    }

    static func repository(_ name: String, isPrivate: Bool = false) -> String {
        #"""
        {"type": "repository", "full_name": "\#(name)", "name": "\#(name.split(separator: "/").last ?? "")",
         "is_private": \#(isPrivate), "updated_on": "2026-11-04T11:48:34.614213+00:00",
         "mainbranch": {"name": "master", "type": "branch"},
         "links": {"html": {"href": "https://bitbucket.org/\#(name)"}}}
        """#
    }

    static func pullRequest(
        _ id: Int,
        repo: String = "atlassian/atlassian-event",
        state: String = "OPEN",
        draft: Bool = false,
        queued: Bool? = nil,
        hash: String = "6315b3bac849",
        updated: String = "2026-03-13T15:04:43.173842+00:00"
    ) -> String {
        #"""
        {"comment_count": 3, "task_count": 0, "type": "pullrequest", "id": \#(id),
         "title": "[Renovate] Update patches (5.1.x) (patch)", "description": "This PR contains the following updates",
         "state": "\#(state)", "draft": \#(draft),\#(queued.map { " \"queued\": \($0)," } ?? "") "merge_commit": null, "close_source_branch": true, "closed_by": null,
         "author": {"display_name": "psre-renovate-bot",
           "links": {"avatar": {"href": "https://secure.gravatar.com/avatar/6972ee037c9f36360170a86f544071a2?d=https%3A%2F%2Favatar-management--avatars.us-west-2.prod.public.atl-paas.net%2Finitials%2FP-3.png"}},
           "type": "user", "uuid": "{250a442a-3ab3-4fcb-87c3-3c8f3df65ec7}", "account_id": "5d5355e8c6b9320d9ea5b28d", "nickname": "Renovate Bot"},
         "reason": "", "created_on": "2024-05-25T11:48:32.489764+00:00", "updated_on": "\#(updated)",
         "destination": {"branch": {"name": "5.1.x"}, "commit": {"hash": "ecdc2efc4f27", "type": "commit"},
           "repository": {"type": "repository", "full_name": "\#(repo)", "name": "Atlassian Event"}},
         "source": {"branch": {"name": "renovate/5.1.x-patch-patches"}, "commit": {"hash": "\#(hash)", "type": "commit"},
           "repository": {"type": "repository", "full_name": "\#(repo)", "name": "Atlassian Event"}},
         "links": {"html": {"href": "https://bitbucket.org/\#(repo)/pull-requests/\#(id)"},
           "statuses": {"href": "https://api.bitbucket.org/2.0/repositories/\#(repo)/pullrequests/\#(id)/statuses"}},
         "summary": {"type": "rendered", "raw": "This PR contains", "markup": "markdown", "html": "<p>This PR contains</p>"}}
        """#
    }

    static func page(_ values: [String], next: String? = nil) -> String {
        #"{"values": [\#(values.joined(separator: ", "))], "pagelen": 50, "page": 1\#(next.map { #", "next": "\#($0)""# } ?? "")}"#
    }

    /// Een geannoteerde tag (eigen datum en tagger) en een lichte (alleen de commit).
    static let tags = #"""
    {"values": [
      {"name": "9.12.17", "type": "tag", "message": "9.12.17\n", "date": "2026-11-04T09:05:19+00:00",
       "tagger": {"type": "author", "raw": "bambooagent <build-agent@atlassian.com>",
         "user": {"display_name": "Build Agent", "links": {"avatar": {"href": "https://avatar-management--avatars.us-west-2.prod.public.atl-paas.net/initials/BA-4.png"}},
           "type": "user", "uuid": "{f87c782c-77b3-4ad7-bfb2-1054b759bd5f}", "nickname": "bamboo_hg_user"}},
       "target": {"type": "commit", "hash": "a872aeb9c7d66021f78539a28be854f3f0f050b6", "date": "2026-11-04T09:03:36+00:00",
         "author": {"type": "author", "raw": "bambooagent <build-agent@atlassian.com>"}, "message": "Release 9.12.17.\n"},
       "links": {"self": {"href": "https://api.bitbucket.org/2.0/repositories/atlassian/aui/refs/tags/9.12.17"},
         "html": {"href": "https://bitbucket.org/atlassian/aui/commits/tag/9.12.17"}}},
      {"name": "9.12.16", "type": "tag", "message": null, "date": null, "tagger": null,
       "target": {"type": "commit", "hash": "536c8c0bb2d4646e6a2da6694be317f43027a95c", "date": "2026-10-28T08:00:00+00:00",
         "author": {"type": "author", "raw": "Jane Doe <jane@example.com>"}},
       "links": {"html": {"href": "https://bitbucket.org/atlassian/aui/commits/tag/9.12.16"}}}
    ], "pagelen": 100, "page": 1}
    """#

    static func statuses(_ states: [String]) -> String {
        let values = states.enumerated().map { index, state in
            #"""
            {"key": "390211293\#(index)", "type": "build", "state": "\#(state)", "name": "AUI - Atlassian AUI - 10.2.x (AUIB10D2X)",
             "refname": null, "commit": {"hash": "7e21fd330776141bc101fd07b4b597997ff19630", "type": "commit"},
             "url": "https://ecosystem-bamboo.internal.atlassian.com/browse/AUI-AUIB10D2X19-3", "description": "No tests found",
             "created_on": "2026-11-04T09:32:56.390075+00:00", "updated_on": "2026-11-04T09:38:11.156363+00:00"}
            """#
        }
        return #"{"values": [\#(values.joined(separator: ", "))], "pagelen": 100, "page": 1}"#
    }

    static let commits = #"""
    {"values": [
      {"hash": "7e21fd330776141bc101fd07b4b597997ff19630", "message": "Fix the build\n\nCo-authored-by: Sam Smith <sam@example.com>\n",
       "author": {"raw": "Jane Doe <jane@example.com>", "user": {"display_name": "Jane Doe", "nickname": "jdoe", "uuid": "{aaaa}"}}},
      {"hash": "536c8c0bb2d4646e6a2da6694be317f43027a95c", "message": "Tidy up\n",
       "author": {"raw": "Kim Lee <kim@example.com>"}}
    ], "pagelen": 100, "page": 1}
    """#

    static func tree(_ entries: [(String, String)], next: String? = nil) -> String {
        let values = entries.map { #"{"path": "\#($0.0)", "type": "\#($0.1)"}"# }.joined(separator: ",")
        return #"{"values":[\#(values)]\#(next.map { #","next":"\#($0)""# } ?? "")}"#
    }
}
