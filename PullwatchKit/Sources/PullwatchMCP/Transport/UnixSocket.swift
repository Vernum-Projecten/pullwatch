import Darwin
public import Foundation
import PullwatchCore

/// De Unix-domain-socket tussen `pullwatch-mcp` en de app: het pad en de systeemaanroepen om er
/// een te maken, te verbinden en in te stellen.
public enum UnixSocket {
    /// `mcp.sock` in de datamap van Pullwatch (`~/Library/Application Support/Pullwatch`, of
    /// `-PullwatchDataDirectory`), naast config.json.
    public static func url(defaults: UserDefaults = .standard) -> URL {
        AppPaths.file("mcp.sock", defaults: defaults)
    }

    /// Verbindt met de socket op `url`. Gooit als daar niets luistert (`ENOENT`, of
    /// `ECONNREFUSED` bij een achtergebleven bestand).
    package static func connect(to url: URL) throws -> NonBlockingDescriptor {
        let descriptor = try make()
        do {
            try withAddress(of: url) { address, length in
                Darwin.connect(descriptor, address, length) == 0 ? nil : errno
            }
            return try NonBlockingDescriptor(adopting: descriptor)
        } catch {
            _ = Darwin.close(descriptor)
            throw error
        }
    }

    /// Een nieuwe stream-socket die bij schrijven naar een gesloten verbinding een fout geeft in
    /// plaats van het proces met `SIGPIPE` te stoppen.
    package static func make() throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw MCPSocketError.system("socket", errno) }
        do {
            try ignoreBrokenPipe(descriptor)
        } catch {
            _ = Darwin.close(descriptor)
            throw error
        }
        return descriptor
    }

    /// `SO_NOSIGPIPE`: een verbinding die de andere kant sloot, geeft `EPIPE`.
    package static func ignoreBrokenPipe(_ descriptor: Int32) throws {
        var on: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw MCPSocketError.system("setsockopt", errno)
        }
    }

    /// Roept `body` aan met een `sockaddr_un` voor `url`; `body` geeft `errno` bij een fout.
    package static func withAddress(
        of url: URL,
        _ body: (UnsafePointer<sockaddr>, socklen_t) -> Int32?
    ) throws {
        let path = url.path(percentEncoded: false)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        // Eén byte voor de afsluitende nul.
        guard bytes.count < capacity else { throw MCPSocketError.pathTooLong(path) }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let failure = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if let failure { throw MCPSocketError.system("connect or bind", failure) }
    }
}
