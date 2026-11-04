import Darwin
import Foundation

/// De luisterende socket van de app op `mcp.sock`. De map wordt 0700 en de socket 0600, zodat
/// alleen de gebruiker zelf kan verbinden; een achtergebleven socket van een vorige run (een crash,
/// een update) wordt eerst weggehaald. `close()` haalt het bestand weg, maar alleen als het nog
/// het eigen bestand is.
package final class MCPSocketListener: Sendable {
    package let url: URL
    private let descriptor: NonBlockingDescriptor
    /// Apparaat en inode van het socketbestand dat deze listener maakte.
    private let identity: FileIdentity

    private struct FileIdentity: Sendable, Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private init(url: URL, descriptor: NonBlockingDescriptor, identity: FileIdentity) {
        self.url = url
        self.descriptor = descriptor
        self.identity = identity
    }

    deinit {
        close()
    }

    /// Opent de socket op `url`. Gooit `inUse` als daar al een Pullwatch luistert.
    package static func open(at url: URL, backlog: Int32 = 8) throws -> MCPSocketListener {
        let path = url.path(percentEncoded: false)
        try prepareDirectory(url.deletingLastPathComponent())
        try removeStaleSocket(at: url)

        let socket = try UnixSocket.make()
        do {
            try UnixSocket.withAddress(of: url) { address, length in
                bind(socket, address, length) == 0 ? nil : errno
            }
            // Voor `listen`: tot dan weigert de socket elke verbinding, ook als de umask hem even
            // ruimer maakte.
            guard chmod(path, 0o600) == 0 else { throw MCPSocketError.system("chmod", errno) }
            var info = stat()
            guard lstat(path, &info) == 0 else { throw MCPSocketError.system("lstat", errno) }
            guard listen(socket, backlog) == 0 else { throw MCPSocketError.system("listen", errno) }
            let descriptor = try NonBlockingDescriptor(adopting: socket)
            return MCPSocketListener(url: url, descriptor: descriptor, identity: FileIdentity(device: info.st_dev, inode: info.st_ino))
        } catch {
            _ = Darwin.close(socket)
            throw error
        }
    }

    /// Maakt de map met 0700, of zet een bestaande map op 0700.
    private static func prepareDirectory(_ directory: URL) throws {
        let path = directory.path(percentEncoded: false)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw MCPSocketError.system("mkdir", EACCES)
        }
        guard chmod(path, 0o700) == 0 else { throw MCPSocketError.system("chmod", errno) }
    }

    /// Haalt een socketbestand weg waar niemand meer op luistert. Luistert er wel iemand (een
    /// tweede Pullwatch met dezelfde datamap), dan blijft het staan.
    private static func removeStaleSocket(at url: URL) throws {
        let path = url.path(percentEncoded: false)
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        if (info.st_mode & S_IFMT) == S_IFSOCK, let live = try? UnixSocket.connect(to: url) {
            live.close()
            throw MCPSocketError.inUse(path)
        }
        guard (info.st_mode & S_IFMT) != S_IFDIR else { throw MCPSocketError.system("bind", EISDIR) }
        guard unlink(path) == 0 else { throw MCPSocketError.system("unlink", errno) }
    }

    // MARK: - Verbindingen

    /// Elke nieuwe verbinding als descriptor, tot `close()` of tot de lezer stopt.
    package func connections() -> AsyncStream<Int32> {
        descriptor.readStream { listening in
            let connection = accept(listening, nil, nil)
            if connection >= 0 { return .element(connection) }
            switch errno {
            case EAGAIN, EINTR, ECONNABORTED:
                return .wouldBlock
            default:
                return .end
            }
        }
    }

    /// Stopt met luisteren maar laat het bestand staan, zoals na een crash. Alleen voor de tests
    /// van het opruimen.
    func closeDescriptorOnlyForTesting() {
        descriptor.close()
    }

    /// Stopt met luisteren en haalt het socketbestand weg, als het nog het eigen bestand is.
    package func close() {
        descriptor.close()
        let path = url.path(percentEncoded: false)
        var info = stat()
        guard lstat(path, &info) == 0, FileIdentity(device: info.st_dev, inode: info.st_ino) == identity else { return }
        _ = unlink(path)
    }
}
