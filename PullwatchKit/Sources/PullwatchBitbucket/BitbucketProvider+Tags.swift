import Foundation
public import PullwatchCore

// MARK: - Tags

/// Bitbucket kent tags maar geen releases (alleen losse bestanden onder Downloads): elke tag komt
/// zonder `ReleaseInfo`, en Tags en releases toont bij Bitbucket dus alleen tags.
extension BitbucketProvider {
    static let tagLimit = 100

    /// Per repo één vraag naar de nieuwste tags (`refs/tags`, op datum van de commit). Een repo die
    /// 404 of geen toegang geeft komt in `unavailableRepos`.
    public func tags(in repos: [String]) async throws -> TagFetch {
        var fetch = TagFetch(tags: [])
        for repo in repos {
            do {
                fetch.tags += try await tags(of: repo)
            } catch ProviderError.server(status: 404) {
                fetch.unavailableRepos.append(repo) // bestaat niet (meer)
            } catch ProviderError.unauthorized where isExtra(repo) {
                fetch.unavailableRepos.append(repo) // 403: geen toegang tot deze losse repo
            } catch ProviderError.rateLimited where readsWithoutTokenCached(repo) {
                fetch.unavailableRepos.append(repo) // limiet zonder inloggen op; de volgende keer weer
            }
        }
        return fetch
    }

    private func tags(of repo: String) async throws -> [Tag] {
        let anonymous = try await readsAnonymously(repo)
        let page: PageDTO<TagDTO> = try await get(repository(repo, "refs", "tags"), anonymous: anonymous, query: [
            URLQueryItem(name: "sort", value: "-target.date"),
            URLQueryItem(name: "pagelen", value: String(Self.tagLimit)),
        ])
        return page.values.compactMap { makeTag(repo: repo, $0) }
    }

    /// De auteur is de tagger van een geannoteerde tag, anders de auteur van de commit; het
    /// Bitbucket-account als Bitbucket het e-mailadres kent, anders de naam uit git.
    private func makeTag(repo: String, _ dto: TagDTO) -> Tag? {
        guard let url = dto.links?.html?.href.flatMap(URL.init(string:)) ?? Self.webURL(repo, "commits", "tag", dto.name) else {
            return nil
        }
        let person = dto.tagger ?? dto.target?.author
        return Tag(
            accountId: accountId,
            repo: repo,
            name: dto.name,
            authorName: person?.user?.displayName ?? person?.raw.flatMap(Self.name(fromRaw:)),
            authorAvatarURL: person?.user?.links?.avatar?.href.flatMap(URL.init(string:)),
            webURL: url,
            createdAt: (dto.date ?? dto.target?.date).flatMap(DateParsing.parse),
            release: nil
        )
    }

    public func datedTags(in repo: String, limit: Int) async throws -> [Tag] {
        guard limit > 0 else { return [] }
        let tags = try await tags(in: [repo]).tags.compactMap { tag in tag.createdAt.map { (tag, $0) } }
        return tags.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// "Jane Doe <jane@example.com>" wordt "Jane Doe"; zonder naam nil.
    static func name(fromRaw raw: String) -> String? {
        let name = raw.split(separator: "<", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return name.isEmpty ? nil : name
    }

    /// Het e-mailadres uit "Jane Doe <jane@example.com>".
    static func email(fromRaw raw: String) -> String? {
        guard let open = raw.firstIndex(of: "<"), let close = raw.lastIndex(of: ">"), open < close else { return nil }
        let email = raw[raw.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        return email.isEmpty ? nil : email
    }
}
