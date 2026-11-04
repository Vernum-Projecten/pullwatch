import Darwin
import Foundation
import Testing
@testable import PullwatchMCP

/// De luisterende socket: alleen voor de gebruiker zelf, en een achtergebleven bestand weg.
@Suite(.timeLimit(.minutes(1))) struct MCPSocketListenerTests {
    let directory: SocketDirectory

    init() throws {
        directory = try SocketDirectory()
    }

    private func mode(of url: URL) throws -> mode_t {
        var info = stat()
        try #require(lstat(url.path(percentEncoded: false), &info) == 0)
        return info.st_mode
    }

    @Test func `The directory is 0700 and the socket 0600`() throws {
        let nested = directory.url.appending(path: "Pullwatch/mcp.sock")
        let listener = try MCPSocketListener.open(at: nested)
        defer { listener.close() }
        #expect(try mode(of: nested.deletingLastPathComponent()) & 0o777 == 0o700)
        #expect(try mode(of: nested) & 0o777 == 0o600)
        #expect(try mode(of: nested) & S_IFMT == S_IFSOCK)
    }

    @Test func `An existing wider directory becomes 0700`() throws {
        try #require(chmod(directory.url.path(percentEncoded: false), 0o755) == 0)
        let listener = try MCPSocketListener.open(at: directory.socket)
        defer { listener.close() }
        #expect(try mode(of: directory.url) & 0o777 == 0o700)
    }

    @Test func `A stale socket from an earlier run is replaced`() throws {
        let earlier = try MCPSocketListener.open(at: directory.socket)
        // Een crash: de descriptor dicht, het bestand blijft.
        earlier.closeDescriptorOnlyForTesting()
        #expect(FileManager.default.fileExists(atPath: directory.socket.path(percentEncoded: false)))
        #expect(throws: (any Error).self) { try UnixSocket.connect(to: directory.socket) }

        let listener = try MCPSocketListener.open(at: directory.socket)
        defer { listener.close() }
        let client = try UnixSocket.connect(to: directory.socket)
        client.close()
    }

    @Test func `A stale plain file is replaced`() throws {
        try Data("old".utf8).write(to: directory.socket)
        let listener = try MCPSocketListener.open(at: directory.socket)
        defer { listener.close() }
        #expect(try mode(of: directory.socket) & S_IFMT == S_IFSOCK)
    }

    @Test func `A socket another Pullwatch listens on is left alone`() throws {
        let running = try MCPSocketListener.open(at: directory.socket)
        defer { running.close() }
        #expect(throws: MCPSocketError.inUse(directory.socket.path(percentEncoded: false))) {
            try MCPSocketListener.open(at: directory.socket)
        }
        let client = try UnixSocket.connect(to: directory.socket)
        client.close()
    }

    @Test func `Closing removes the socket file`() throws {
        let listener = try MCPSocketListener.open(at: directory.socket)
        listener.close()
        #expect(!FileManager.default.fileExists(atPath: directory.socket.path(percentEncoded: false)))
    }

    @Test func `Closing an old listener leaves the socket of a newer one`() throws {
        let old = try MCPSocketListener.open(at: directory.socket)
        old.closeDescriptorOnlyForTesting()
        let new = try MCPSocketListener.open(at: directory.socket)
        defer { new.close() }
        old.close()
        let client = try UnixSocket.connect(to: directory.socket)
        client.close()
    }

    @Test func `Each connection comes out of the listener`() async throws {
        let listener = try MCPSocketListener.open(at: directory.socket)
        defer { listener.close() }
        var connections = listener.connections().makeAsyncIterator()
        let first = try UnixSocket.connect(to: directory.socket)
        let second = try UnixSocket.connect(to: directory.socket)
        let one = try #require(await connections.next())
        let two = try #require(await connections.next())
        #expect(one != two)
        close(one)
        close(two)
        first.close()
        second.close()
    }

    @Test func `A path that does not fit a socket address is refused`() {
        let long = directory.url.appending(path: String(repeating: "a", count: 120))
        #expect(throws: MCPSocketError.pathTooLong(long.path(percentEncoded: false))) {
            try MCPSocketListener.open(at: long)
        }
    }
}
