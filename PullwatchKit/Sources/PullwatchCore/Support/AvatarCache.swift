import CryptoKit
import Foundation

/// Profielfoto's voor meldingen (`UNNotificationAttachment`): één keer opgehaald met de
/// `HTTPClient` van de app, klein (`size`), en een week bewaard in `directory`. macOS verplaatst
/// het bestand van een bijlage naar zijn eigen opslag, dus elke melding krijgt een verse kopie
/// (`attachmentFile`). Wat geen PNG, JPEG of GIF is, of groter dan `maxBytes`, komt er niet in.
public actor AvatarCache {
    public static let maxBytes = 512 * 1024
    public static let maxAge: TimeInterval = 7 * 24 * 3600

    private let http: any HTTPClient
    private let directory: URL
    private let now: @Sendable () -> Date
    /// Lopende downloads, zodat tien PR's van dezelfde auteur één verzoek geven.
    private var running: [URL: Task<URL?, Never>] = [:]

    public init(http: any HTTPClient, directory: URL, now: @escaping @Sendable () -> Date = Date.init) {
        self.http = http
        self.directory = directory
        self.now = now
    }

    /// Het bewaarde bestand van deze foto; ophalen als het er nog niet (of te lang) is. Nil als
    /// het niet lukt: de melding krijgt dan het teken van de soort.
    public func cachedFile(for url: URL) async -> URL? {
        let file = directory.appending(path: Self.fileName(for: url))
        if let modified = (try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false)))?[.modificationDate] as? Date,
           now().timeIntervalSince(modified) < Self.maxAge {
            return file
        }
        if let task = running[url] { return await task.value }
        let http = http
        let directory = directory
        let task = Task<URL?, Never> {
            await Self.download(url, to: file, in: directory, http: http)
        }
        running[url] = task
        let result = await task.value
        running[url] = nil
        return result
    }

    /// Een kopie van de foto om aan één melding te hangen, in een eigen tijdelijke map en met de
    /// extensie van het echte type (daaraan herkent macOS het plaatje).
    public func attachmentFile(for url: URL) async -> URL? {
        guard let cached = await cachedFile(for: url),
              let data = try? Data(contentsOf: cached),
              let ext = Self.imageExtension(data) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appending(path: "pullwatch-attachments/\(UUID().uuidString)")
        let copy = folder.appending(path: "avatar.\(ext)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: copy)
            return copy
        } catch {
            return nil
        }
    }

    private static func download(_ url: URL, to file: URL, in directory: URL, http: any HTTPClient) async -> URL? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await http.send(request)
            guard (200..<300).contains(response.statusCode), data.count <= maxBytes, imageExtension(data) != nil else { return nil }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            return file
        } catch {
            return nil
        }
    }

    /// "png", "jpg" of "gif" naar de eerste bytes; nil voor iets anders (bv. een HTML-loginpagina).
    static func imageExtension(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        return nil
    }

    /// Vast per adres en zonder tekens die een bestandsnaam niet mag hebben.
    static func fileName(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
