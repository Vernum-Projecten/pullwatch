import Foundation
import PullwatchCore

// MARK: - Bestanden

extension GitLabProvider {
    /// Alle bestanden op `ref` (zonder: de default branch), via de boom (`recursive=true`). Een
    /// lege repo heeft geen boom: GitLab geeft dan 404, dat wordt een lege lijst.
    public func filePaths(in repo: String, ref: String?) async throws -> [String] {
        var query = [URLQueryItem(name: "recursive", value: "true")]
        if let ref { query.append(URLQueryItem(name: "ref", value: ref)) }
        let entries: [TreeEntryDTO]
        do {
            entries = try await pages(
                endpoint("projects", repo, "repository", "tree"), query: query, maxPages: maxTreePages,
                anonymous: try await readsAnonymously(repo)
            )
        } catch ProviderError.server(status: 404) {
            return []
        }
        return entries.filter { $0.type == "blob" }.map(\.path)
    }

    /// Eén bestand als tekst (`repository/files/:pad/raw`); het hele pad is één gecodeerd segment.
    public func fileContent(in repo: String, path: String, ref: String?) async throws -> String {
        let data = try await send(
            endpoint("projects", repo, "repository", "files", path, "raw"),
            query: ref.map { [URLQueryItem(name: "ref", value: $0)] } ?? [],
            anonymous: try await readsAnonymously(repo)
        ).data
        return String(decoding: data, as: UTF8.self)
    }
}
