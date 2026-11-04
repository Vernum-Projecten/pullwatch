import Foundation
import PullwatchCore

// MARK: - Bestanden

extension AzureDevOpsProvider {
    public func filePaths(in repo: String, ref: String?) async throws -> [String] {
        let list: ValueList<ItemDTO>
        do {
            list = try await get(itemsURL(repo), query: [
                URLQueryItem(name: "scopePath", value: "/"),
                URLQueryItem(name: "recursionLevel", value: "Full"),
            ] + versionQuery(ref))
        } catch ProviderError.server(status: 404) {
            return [] // lege repo
        }
        return list.value.filter { $0.isFolder != true }.map { String($0.path.drop { $0 == "/" }) }
    }

    public func fileContent(in repo: String, path: String, ref: String?) async throws -> String {
        let item: ItemDTO = try await get(itemsURL(repo), query: [
            URLQueryItem(name: "path", value: "/" + path),
            URLQueryItem(name: "includeContent", value: "true"),
        ] + versionQuery(ref))
        return item.content ?? ""
    }

    /// Zonder tag leest Azure DevOps de default branch.
    private func versionQuery(_ tag: String?) -> [URLQueryItem] {
        guard let tag else { return [] }
        return [
            URLQueryItem(name: "versionDescriptor.version", value: tag),
            URLQueryItem(name: "versionDescriptor.versionType", value: "tag"),
        ]
    }

    /// `repo` is "project/naam", zoals `listRepos()` levert.
    private func itemsURL(_ repo: String) -> URL {
        let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
        return baseURL.appending(path: parts.first ?? repo).appending(path: "_apis/git/repositories")
            .appending(path: parts.last ?? repo).appending(path: "items")
    }
}
