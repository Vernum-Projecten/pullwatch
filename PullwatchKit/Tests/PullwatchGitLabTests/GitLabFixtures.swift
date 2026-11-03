import Foundation

/// Antwoorden in de vorm die GitLab (REST v4) echt geeft, ingekort tot de velden die ertoe doen
/// plus een paar die Pullwatch moet negeren.
enum GitLabFixtures {
    static let user = #"""
    {"id":42,"username":"jdoe","name":"Jane Doe","state":"active","locked":false,
     "avatar_url":"https://gitlab.com/uploads/-/system/user/avatar/42/avatar.png",
     "web_url":"https://gitlab.com/jdoe","created_at":"2020-01-02T10:00:00.000Z"}
    """#

    static let group = #"""
    {"id":7,"web_url":"https://gitlab.com/groups/acme","name":"Acme","path":"acme",
     "description":"","visibility":"private","full_name":"Acme","full_path":"acme","parent_id":null}
    """#

    static let subgroup = #"""
    {"id":8,"web_url":"https://gitlab.com/groups/acme/platform","name":"Platform","path":"platform",
     "visibility":"private","full_name":"Acme / Platform","full_path":"acme/platform","parent_id":7}
    """#

    static func users(_ username: String, id: Int) -> String {
        #"""
        [{"id":\#(id),"username":"\#(username)","name":"\#(username.capitalized)","state":"active",
          "avatar_url":"https://gitlab.com/uploads/-/system/user/avatar/\#(id)/avatar.png",
          "web_url":"https://gitlab.com/\#(username)"}]
        """#
    }

    static func project(_ path: String, id: Int) -> String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return #"""
        {"id":\#(id),"name":"\#(name)","name_with_namespace":"\#(path.replacingOccurrences(of: "/", with: " / "))",
         "path":"\#(name)","path_with_namespace":"\#(path)","created_at":"2021-03-04T09:00:00.000Z",
         "default_branch":"main","web_url":"https://gitlab.com/\#(path)","avatar_url":null,
         "namespace":{"id":7,"name":"Acme","path":"acme","kind":"group","full_path":"acme"}}
        """#
    }

    static func mergeRequest(
        iid: Int,
        project: String = "acme/platform/api",
        state: String = "opened",
        draft: Bool = false,
        author: String = "alice",
        authorName: String = "Alice Example",
        mergedAt: String? = nil,
        closedAt: String? = nil,
        sha: String = "a1b2c3d4",
        autoMerge: Bool = false
    ) -> String {
        let merged = mergedAt.map { "\"\($0)\"" } ?? "null"
        let closed = closedAt.map { "\"\($0)\"" } ?? "null"
        return #"""
        {"id":\#(1000 + iid),"iid":\#(iid),"project_id":99,"title":"MR \#(iid)","description":"Body",
         "state":"\#(state)","created_at":"2025-10-15T10:00:00.123Z","updated_at":"2025-10-16T11:00:00.000Z",
         "merged_by":null,"merged_at":\#(merged),"closed_by":null,"closed_at":\#(closed),
         "target_branch":"main","source_branch":"feature-\#(iid)","user_notes_count":2,
         "author":{"id":5,"username":"\#(author)","name":"\#(authorName)","state":"active",
                   "avatar_url":"https://gitlab.com/uploads/-/system/user/avatar/5/avatar.png",
                   "web_url":"https://gitlab.com/\#(author)"},
         "draft":\#(draft),"work_in_progress":\#(draft),"merge_status":"can_be_merged",
         "merge_when_pipeline_succeeds":\#(autoMerge),"sha":"\#(sha)","merge_commit_sha":null,
         "references":{"short":"!\#(iid)","relative":"!\#(iid)","full":"\#(project)!\#(iid)"},
         "web_url":"https://gitlab.com/\#(project)/-/merge_requests/\#(iid)"}
        """#
    }

    /// Een geannoteerde tag (met eigen `created_at`) of een lichte (zonder), met of zonder release.
    static func tag(_ name: String, created: String?, committed: String, author: String, release: Bool) -> String {
        let createdField = created.map { "\"\($0)\"" } ?? "null"
        let releaseField = release ? #"{"tag_name":"\#(name)","description":"Notes"}"# : "null"
        return #"""
        {"name":"\#(name)","message":"","target":"f00d","protected":true,"created_at":\#(createdField),
         "commit":{"id":"f00dcafe","short_id":"f00dcafe","title":"Release \#(name)","message":"Release \#(name)",
                   "parent_ids":["beef"],"author_name":"\#(author)","author_email":"dev@example.com",
                   "authored_date":"\#(committed)","committer_name":"\#(author)","committer_email":"dev@example.com",
                   "committed_date":"\#(committed)","created_at":"\#(committed)",
                   "web_url":"https://gitlab.com/acme/platform/api/-/commit/f00dcafe"},
         "release":\#(releaseField)}
        """#
    }

    static func release(_ tag: String, name: String, author: String, project: String = "acme/platform/api",
                        avatar: String = "https://gitlab.com/uploads/-/system/user/avatar/9/avatar.png") -> String {
        #"""
        {"name":"\#(name)","tag_name":"\#(tag)","description":"Notes","created_at":"2025-09-01T12:00:00.000Z",
         "released_at":"2025-09-01T12:30:00.000Z","upcoming_release":false,
         "author":{"id":9,"username":"\#(author)","name":"\#(author)","state":"active",
                   "avatar_url":"\#(avatar)",
                   "web_url":"https://gitlab.com/\#(author)"},
         "commit":{"id":"f00dcafe"},
         "_links":{"self":"https://gitlab.com/\#(project)/-/releases/\#(tag)",
                   "edit_url":"https://gitlab.com/\#(project)/-/releases/\#(tag)/edit"}}
        """#
    }

    static func commit(author: String, email: String, message: String) -> String {
        let escaped = message.replacingOccurrences(of: "\n", with: "\\n")
        return #"""
        {"id":"\#(UUID().uuidString)","short_id":"abc","title":"t","author_name":"\#(author)","author_email":"\#(email)",
         "authored_date":"2025-10-15T10:00:00.000Z","committer_name":"\#(author)","committer_email":"\#(email)",
         "committed_date":"2025-10-15T10:00:00.000Z","created_at":"2025-10-15T10:00:00.000Z",
         "message":"\#(escaped)","parent_ids":[],"web_url":"https://gitlab.com/x/-/commit/abc"}
        """#
    }

    static func tree(_ entries: [(path: String, type: String)]) -> String {
        "[" + entries.map { entry in
            let name = entry.path.split(separator: "/").last.map(String.init) ?? entry.path
            return #"{"id":"aa","name":"\#(name)","type":"\#(entry.type)","path":"\#(entry.path)","mode":"100644"}"#
        }.joined(separator: ",") + "]"
    }
}
