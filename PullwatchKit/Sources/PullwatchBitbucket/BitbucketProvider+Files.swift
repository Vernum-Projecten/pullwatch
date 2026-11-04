import Foundation
import PullwatchCore

// MARK: - Bestanden

extension BitbucketProvider {
    /// Zo diep leest `/src` de mappen in één lijst (`max_depth`).
    static let maxTreeDepth = 50

    /// Alle bestanden op `ref` (zonder: `HEAD`, de standaardbranch), via `/src/{ref}/` met
    /// `max_depth`, zodat de hele boom in een paar pagina's komt. Een lege repo heeft geen
    /// commit: Bitbucket geeft dan 404, dat wordt een lege lijst.
    public func filePaths(in repo: String, ref: String?) async throws -> [String] {
        let entries: [TreeEntryDTO]
        do {
            entries = try await pages(
                Self.directory(repository(repo, "src", ref ?? "HEAD")),
                query: [
                    URLQueryItem(name: "pagelen", value: String(pageSize)),
                    URLQueryItem(name: "max_depth", value: String(Self.maxTreeDepth)),
                    URLQueryItem(name: "fields", value: "next,values.path,values.type"),
                ],
                maxPages: maxTreePages, anonymous: try await readsAnonymously(repo)
            )
        } catch ProviderError.server(status: 404) {
            return []
        }
        return entries.filter { $0.type == "commit_file" }.map(\.path)
    }

    /// Eén bestand als tekst (`/src/{ref}/{pad}`, de ruwe inhoud).
    public func fileContent(in repo: String, path: String, ref: String?) async throws -> String {
        var url = repository(repo, "src", ref ?? "HEAD")
        for part in path.split(separator: "/") { url = URL(string: url.absoluteString + "/" + Self.encode(String(part)))! }
        let data = try await send(url, anonymous: try await readsAnonymously(repo)).data
        return String(decoding: data, as: UTF8.self)
    }

    /// De map zelf, met "/" aan het eind: zonder geeft Bitbucket de inhoud van een bestand.
    private static func directory(_ url: URL) -> URL {
        URL(string: url.absoluteString + "/")!
    }
}
