import Foundation

// De antwoorden van de REST API van Azure DevOps.

struct ValueList<T: Decodable>: Decodable {
    let value: [T]
}

struct ItemDTO: Decodable {
    let path: String
    let isFolder: Bool?
    let content: String?
}

struct ConnectionData: Decodable {
    static let anonymousUserId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

    struct User: Decodable {
        let id: String
        let providerDisplayName: String?
    }
    let authenticatedUser: User
}

struct ProjectDTO: Decodable {
    let name: String
}

struct RepositoryDTO: Decodable {
    let name: String
}

struct SingleRepositoryDTO: Decodable {
    struct Project: Decodable { let name: String }
    let name: String
    let project: Project
}

struct PullRequestDTO: Decodable {
    struct Identity: Decodable {
        let id: String
        let displayName: String
        /// Meestal het e-mailadres.
        let uniqueName: String?
    }

    struct CommitRef: Decodable { let commitId: String }

    struct Repository: Decodable {
        struct Project: Decodable {
            let name: String
            let id: String?
        }
        let name: String
        let project: Project
    }

    let pullRequestId: Int
    let title: String
    let isDraft: Bool?
    let status: String?
    let closedDate: String?
    let creationDate: String
    let createdBy: Identity
    let repository: Repository
    /// De laatste commit van de bronbranch; verandert bij elke push.
    let lastMergeSourceCommit: CommitRef?
    /// Wie auto-complete aanzette; ontbreekt als het uit staat.
    let autoCompleteSetBy: Identity?
}

/// Een commit van een PR, of los opgehaald voor het volledige bericht.
struct PRCommitDTO: Decodable {
    struct Person: Decodable {
        let name: String?
        let email: String?
    }
    let commitId: String
    let author: Person?
    let comment: String?
    let commentTruncated: Bool?
}

struct RefDTO: Decodable {
    struct Creator: Decodable { let displayName: String }
    let name: String
    let creator: Creator?
    let objectId: String?
    /// Bij `peelTags=true` de commit achter een geannoteerde tag.
    let peeledObjectId: String?
}

struct CommitsBatchDTO: Encodable {
    let ids: [String]
    let top: Int

    private enum CodingKeys: String, CodingKey {
        case ids
        case top = "$top"
    }
}

struct AnnotatedTagDTO: Decodable {
    struct UserDate: Decodable { let name: String? }
    let taggedBy: UserDate?
}

struct CommitDTO: Decodable {
    struct Person: Decodable {
        let name: String?
        let email: String?
        let date: String?
    }
    let commitId: String
    let author: Person?
    let committer: Person?
}

/// `diffs/commits`: hoeveel commits de doel-versie voor of achter ligt op de basis.
struct CommitDiffsDTO: Decodable {
    let aheadCount: Int
    let behindCount: Int
}
