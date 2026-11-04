import Foundation

// De antwoorden van de REST API van GitHub (snake_case, `JSONDecoding` met `snakeCase: true`).

struct UserDTO: Decodable {
    let login: String
}

struct OwnerDTO: Decodable {
    let type: String
}

struct RepoDTO: Decodable {
    let fullName: String
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
