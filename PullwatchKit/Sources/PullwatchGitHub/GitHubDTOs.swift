import Foundation

// De antwoorden van de REST API van GitHub (snake_case, `JSONDecoding` met `snakeCase: true`).

struct UserDTO: Decodable {
    let login: String
    /// De foto die GitHub zelf geeft: `avatars.githubusercontent.com/u/…`, voor een bot (een
    /// GitHub App) `…/in/<app-id>`, op GitHub Enterprise de eigen server.
    let avatarUrl: String?
}

struct OwnerDTO: Decodable {
    let type: String
}

struct RepoDTO: Decodable {
    let fullName: String
}

/// `GET /repos/{repo}/compare/{base}...{head}`: hoeveel commits `head` voor en achter ligt.
struct CompareDTO: Decodable {
    let aheadBy: Int
    let behindBy: Int
}

/// Eén branch uit `GET /repos/{repo}/branches`: alleen naam en sha, zonder datum of auteur.
struct BranchDTO: Decodable {
    struct Commit: Decodable {
        let sha: String
    }

    let name: String
    let commit: Commit
}

struct SearchDTO: Decodable {
    struct PullRequestInfo: Decodable {
        let mergedAt: String?
    }

    struct Item: Decodable {
        let number: Int
        let title: String
        let createdAt: String
        let updatedAt: String?
        let draft: Bool?
        let state: String?
        let closedAt: String?
        let pullRequest: PullRequestInfo?
        let user: UserDTO
        let htmlUrl: String
        let repositoryUrl: String
    }

    let totalCount: Int
    let items: [Item]
}

struct TreeDTO: Decodable {
    struct Entry: Decodable {
        let path: String
        let type: String
    }

    let tree: [Entry]
}
