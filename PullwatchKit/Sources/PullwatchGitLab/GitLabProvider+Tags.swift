import Foundation
import PullwatchCore

// MARK: - Tags

extension GitLabProvider {
    /// Per repo één vraag naar de tags (nieuwste eerst, met de commit erachter) en alleen als een
    /// tag een release heeft een tweede naar de releases (titel, auteur, datum). Een repo die 404
    /// of 403 geeft komt in `unavailableRepos`.
    public func tags(in repos: [String]) async throws -> TagFetch {
        var fetch = TagFetch(tags: [])
        for repo in repos {
            do {
                fetch.tags += try await tags(of: repo)
            } catch ProviderError.server(status: 404) {
                fetch.unavailableRepos.append(repo) // bestaat niet (meer)
            } catch ProviderError.unauthorized {
                fetch.unavailableRepos.append(repo) // 403: geen toegang tot de repository
            } catch ProviderError.rateLimited where readsWithoutTokenCached(repo) {
                fetch.unavailableRepos.append(repo) // limiet zonder token op; de volgende keer weer
            }
        }
        return fetch
    }

    static let tagLimit = 100
    static let releaseLimit = 20

    private func tags(of repo: String) async throws -> [Tag] {
        let anonymous = try await readsAnonymously(repo)
        let tags: [TagDTO] = try await get(endpoint("projects", repo, "repository", "tags"), anonymous: anonymous, query: [
            URLQueryItem(name: "order_by", value: "updated"),
            URLQueryItem(name: "sort", value: "desc"),
            URLQueryItem(name: "per_page", value: String(Self.tagLimit)),
        ])
        var releases: [String: ReleaseDTO] = [:]
        if tags.contains(where: { $0.release != nil }) {
            let list: [ReleaseDTO] = try await get(endpoint("projects", repo, "releases"), anonymous: anonymous, query: [
                URLQueryItem(name: "order_by", value: "released_at"),
                URLQueryItem(name: "sort", value: "desc"),
                URLQueryItem(name: "per_page", value: String(Self.releaseLimit)),
            ])
            for release in list where releases[release.tagName] == nil { releases[release.tagName] = release }
        }
        return tags.compactMap { makeTag(repo: repo, $0, release: releases[$0.name]) }
    }

    /// De auteur is wie de release maakte, maar een bot maakt plaats voor de auteur van de commit:
    /// die persoon zette de release echt in gang.
    private func makeTag(repo: String, _ dto: TagDTO, release: ReleaseDTO?) -> Tag? {
        guard let tagURL = webURL(repo, "-", "tags", dto.name) else { return nil }
        let releaseInfo = release.map { release in
            ReleaseInfo(
                title: release.name,
                authorLogin: release.author?.username,
                authorAvatarURL: release.author?.avatarUrl.flatMap(URL.init(string:)),
                isPrerelease: false, // GitLab kent geen pre-releases
                publishedAt: (release.releasedAt ?? release.createdAt).flatMap(DateParsing.parse),
                url: release.links?.selfURL.flatMap(URL.init(string:)) ?? webURL(repo, "-", "releases", dto.name) ?? tagURL
            )
        }
        let releaseAuthor = release?.author.map { (name: $0.username, avatar: $0.avatarUrl.flatMap(URL.init(string:))) }
        let commitAuthor = dto.commit?.authorName.flatMap { $0.isEmpty ? nil : (name: $0, avatar: URL?.none) }
        let people = [releaseAuthor.flatMap { Self.isBot($0.name) ? nil : $0 }, commitAuthor, releaseAuthor]
        let author = people.compactMap { $0 }.first
        return Tag(
            accountId: accountId,
            repo: repo,
            name: dto.name,
            authorName: author?.name,
            authorAvatarURL: author?.avatar,
            webURL: releaseInfo?.url ?? tagURL,
            // Een geannoteerde tag heeft een eigen datum, een lichte die van zijn commit.
            createdAt: (dto.createdAt ?? dto.commit?.committedDate ?? dto.commit?.createdAt).flatMap(DateParsing.parse),
            release: releaseInfo
        )
    }

    public func datedTags(in repo: String, limit: Int) async throws -> [Tag] {
        guard limit > 0 else { return [] }
        let tags = try await tags(in: [repo]).tags.compactMap { tag in tag.createdAt.map { (tag, $0) } }
        return tags.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// GitLab-bots: projecttokens en groepstokens (`project_12_bot_…`, `group_3_bot_…`), de
    /// beveiligingsbots, en GitHub-achtige namen met "[bot]".
    static func isBot(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("[bot]") || lower.contains("_bot_") || lower.hasSuffix("_bot") || lower.hasSuffix("-bot")
    }
}
