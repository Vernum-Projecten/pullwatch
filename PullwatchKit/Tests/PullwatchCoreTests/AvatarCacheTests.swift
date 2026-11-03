import Foundation
import Testing
@testable import PullwatchCore

/// Geeft vaste bytes terug (MockHTTPClient kent alleen tekst) en telt de verzoeken.
private final class BytesClient: HTTPClient, @unchecked Sendable {
    let body: Data
    let status: Int
    private let lock = NSLock()
    private var count = 0

    init(body: Data, status: Int = 200) {
        self.body = body
        self.status = status
    }

    var requests: Int { lock.withLock { count } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { count += 1 }
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite struct AvatarCacheTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])
    private let url = URL(string: "https://github.com/mona.png?size=64")!

    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "avatar-tests-\(UUID().uuidString)")
    }

    @Test func downloadsOnceAndHandsOutAFreshCopyEachTime() async throws {
        let client = BytesClient(body: png)
        let cache = AvatarCache(http: client, directory: folder())
        let first = try #require(await cache.attachmentFile(for: url))
        let second = try #require(await cache.attachmentFile(for: url))
        #expect(first != second)
        #expect(first.pathExtension == "png")
        #expect(try Data(contentsOf: first) == png)
        #expect(client.requests == 1)
        // macOS mag de kopie wegnemen; de bewaarde foto blijft.
        try FileManager.default.removeItem(at: first)
        #expect(await cache.attachmentFile(for: url) != nil)
        #expect(client.requests == 1)
    }

    @Test func anOldFileIsFetchedAgain() async throws {
        let client = BytesClient(body: png)
        let directory = folder()
        let later = AvatarCache(http: client, directory: directory, now: { Date() + AvatarCache.maxAge + 60 })
        _ = await AvatarCache(http: client, directory: directory).cachedFile(for: url)
        _ = await later.cachedFile(for: url)
        #expect(client.requests == 2)
    }

    @Test func refusesWhatIsNotASmallImage() async {
        let html = BytesClient(body: Data("<html>login</html>".utf8))
        #expect(await AvatarCache(http: html, directory: folder()).attachmentFile(for: url) == nil)
        let huge = BytesClient(body: png + Data(count: AvatarCache.maxBytes))
        #expect(await AvatarCache(http: huge, directory: folder()).attachmentFile(for: url) == nil)
        let missing = BytesClient(body: png, status: 404)
        #expect(await AvatarCache(http: missing, directory: folder()).attachmentFile(for: url) == nil)
    }

    @Test func recognisesImageTypesAndNamesFilesStably() {
        #expect(AvatarCache.imageExtension(png) == "png")
        #expect(AvatarCache.imageExtension(Data([0xFF, 0xD8, 0xFF, 0xE0])) == "jpg")
        #expect(AvatarCache.imageExtension(Data("GIF89a".utf8)) == "gif")
        #expect(AvatarCache.imageExtension(Data()) == nil)
        #expect(AvatarCache.fileName(for: url) == AvatarCache.fileName(for: URL(string: url.absoluteString)!))
        #expect(AvatarCache.fileName(for: url) != AvatarCache.fileName(for: URL(string: "https://github.com/hubot.png")!))
        #expect(AvatarCache.fileName(for: url).count == 32)
    }
}
