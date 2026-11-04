import Foundation
import PullwatchCore

// MARK: - Bestanden

extension GiteaProvider {
    /// Alle bestanden op `ref` (zonder: `HEAD`, de default branch), via de boom met
    /// `recursive=true`, duizend paden per pagina. Een lege repo heeft geen boom: de server geeft
    /// dan 404 (of 409), dat wordt een lege lijst.
    public func filePaths(in repo: String, ref: String?) async throws -> [String] {
        let anonymous = try await readsAnonymously(repo)
        let url = repoEndpoint(repo, "git", "trees", ref ?? "HEAD")
        var paths: [String] = []
        var seen = 0
        for page in 1...maxTreePages {
            let tree: TreeDTO
            do {
                tree = try await get(url, anonymous: anonymous, query: [
                    URLQueryItem(name: "recursive", value: "true"),
                    URLQueryItem(name: "per_page", value: "1000"),
                    URLQueryItem(name: "page", value: String(page)),
                ])
            } catch ProviderError.server(status: let status) where status == 404 || status == 409 {
                return paths
            }
            let entries = tree.tree ?? []
            seen += entries.count
            paths += entries.filter { $0.type == "blob" }.map(\.path)
            // `truncated` staat bij pagineren altijd aan; het totaal zegt wanneer het klaar is.
            guard !entries.isEmpty, let total = tree.totalCount, seen < total else { break }
        }
        return paths
    }

    /// Eén bestand als tekst (`raw/:pad`); elk deel van het pad apart gecodeerd.
    public func fileContent(in repo: String, path: String, ref: String?) async throws -> String {
        var segments: [String] = ["repos"]
        segments += repo.split(separator: "/", maxSplits: 1).map(String.init)
        segments.append("raw")
        segments += path.split(separator: "/").map(String.init)
        let data = try await send(
            endpoint(segments),
            query: ref.map { [URLQueryItem(name: "ref", value: $0)] } ?? [],
            anonymous: try await readsAnonymously(repo)
        ).data
        return String(decoding: data, as: UTF8.self)
    }
}
