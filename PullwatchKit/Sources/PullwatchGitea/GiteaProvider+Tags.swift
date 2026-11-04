import Foundation
public import PullwatchCore

// MARK: - Tags

extension GiteaProvider {
    /// Per repo één vraag naar de tags (nieuwste eerst, met de datum van hun commit) en één naar de
    /// releases (titel, auteur, datum, pre-release). Een repo die 404 of 403 geeft komt in
    /// `unavailableRepos`.
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

    static let releaseLimit = 20

    private func tags(of repo: String) async throws -> [Tag] {
        let anonymous = try await readsAnonymously(repo)
        let tags: [TagDTO] = try await get(repoEndpoint(repo, "tags"), anonymous: anonymous, query: [
            URLQueryItem(name: "limit", value: String(pageSize)),
        ])
        guard !tags.isEmpty else { return [] }
        let list: [ReleaseDTO] = try await get(repoEndpoint(repo, "releases"), anonymous: anonymous, query: [
            URLQueryItem(name: "draft", value: "false"),
            URLQueryItem(name: "limit", value: String(Self.releaseLimit)),
        ])
        var releases: [String: ReleaseDTO] = [:]
        for release in list where release.draft != true && releases[release.tagName] == nil {
            releases[release.tagName] = release
        }
        return tags.compactMap { makeTag(repo: repo, $0, release: releases[$0.name]) }
    }

    /// Een tag in Gitea heeft geen auteur; met een release is dat wie hem maakte (geen bot).
    private func makeTag(repo: String, _ dto: TagDTO, release: ReleaseDTO?) -> Tag? {
        guard let tagURL = webURL(repo, "src", "tag", dto.name) else { return nil }
        let releaseInfo = release.map { release in
            ReleaseInfo(
                title: release.name.flatMap { $0.isEmpty ? nil : $0 },
                authorLogin: release.author?.login,
                authorAvatarURL: release.author?.avatarUrl.flatMap(URL.init(string:)),
                isPrerelease: release.prerelease ?? false,
                publishedAt: (release.publishedAt ?? release.createdAt).flatMap(DateParsing.parse),
                url: release.htmlUrl.flatMap(URL.init(string:)) ?? webURL(repo, "releases", "tag", dto.name) ?? tagURL
            )
        }
        let author = release?.author.flatMap { Self.isBot($0.login) ? nil : $0 }
        return Tag(
            accountId: accountId,
            repo: repo,
            name: dto.name,
            authorName: author?.login,
            authorAvatarURL: author?.avatarUrl.flatMap(URL.init(string:)),
            webURL: releaseInfo?.url ?? tagURL,
            createdAt: (dto.commit?.created ?? release?.publishedAt).flatMap(DateParsing.parse),
            release: releaseInfo
        )
    }

    public func datedTags(in repo: String, limit: Int) async throws -> [Tag] {
        guard limit > 0 else { return [] }
        let tags = try await tags(in: [repo]).tags.compactMap { tag in tag.createdAt.map { (tag, $0) } }
        return tags.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// Bots: "[bot]" in de naam (Renovate, Dependabot) en namen die op "-bot" of "_bot" eindigen.
    static func isBot(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("[bot]") || lower.hasSuffix("-bot") || lower.hasSuffix("_bot")
    }
}
