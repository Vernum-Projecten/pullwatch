import Foundation
import MCP
import Testing
@testable import PullwatchMCP

/// De transport over een socket: regels in en uit, een te lange regel, sluiten.
@Suite(.timeLimit(.minutes(1))) struct MCPSocketTransportTests {
    @Test func `Messages arrive whole however the bytes are split`() async throws {
        let (near, far) = try socketPair()
        let transport = MCPSocketTransport(descriptor: near)
        try await transport.connect()
        var messages = await transport.receive().makeAsyncIterator()

        try await far.write(Data(#"{"jsonrpc":"2.0","#.utf8))
        try await far.write(Data(#""method":"ping","id":1}"#.utf8))
        try await far.write(Data("\n{\"n\":2}\n{\"n\":3}\n".utf8))

        #expect(try await messages.next() == Data(#"{"jsonrpc":"2.0","method":"ping","id":1}"#.utf8))
        #expect(try await messages.next() == Data(#"{"n":2}"#.utf8))
        #expect(try await messages.next() == Data(#"{"n":3}"#.utf8))
        await transport.disconnect()
        far.close()
    }

    @Test func `Sent messages end in a newline`() async throws {
        let (near, far) = try socketPair()
        let transport = MCPSocketTransport(descriptor: near)
        try await transport.connect()
        let client = LineClient(far)

        try await transport.send(Data(#"{"a":1}"#.utf8))
        try await transport.send(Data(#"{"b":2}"#.utf8))
        #expect(await client.lines.next() == Data(#"{"a":1}"#.utf8))
        #expect(await client.lines.next() == Data(#"{"b":2}"#.utf8))
        await transport.disconnect()
        client.close()
    }

    @Test func `A large answer is written whole even when the socket buffer is full`() async throws {
        let (near, far) = try socketPair()
        let transport = MCPSocketTransport(descriptor: near)
        try await transport.connect()
        let client = LineClient(far)
        let large = Data(#"{"text":"\#(String(repeating: "x", count: 600_000))"}"#.utf8)

        async let first: Void = transport.send(large)
        async let second: Void = transport.send(Data(#"{"after":true}"#.utf8))
        _ = try await (first, second)
        // Welke eerst gaat, is aan de scheduler; wel komt elk bericht heel en apart aan.
        let received: Set<Data> = [try #require(await client.lines.next()), try #require(await client.lines.next())]
        #expect(received == [large, Data(#"{"after":true}"#.utf8)])
        await transport.disconnect()
        client.close()
    }

    @Test func `A line over the limit gets an error and the session goes on`() async throws {
        let (near, far) = try socketPair()
        let transport = MCPSocketTransport(descriptor: near, limits: MCPLimits(maxMessageBytes: 64, maxDepth: 32))
        try await transport.connect()
        var messages = await transport.receive().makeAsyncIterator()
        let client = LineClient(far)

        try await client.send(#"{"padding":"\#(String(repeating: "x", count: 200))"}"#)
        let error = try await client.lines.nextObject()
        #expect(error["error"]?.objectValue?["code"] == .int(-32600))
        #expect(error["id"] == .null)

        try await client.send(#"{"n":1}"#)
        #expect(try await messages.next() == Data(#"{"n":1}"#.utf8))
        await transport.disconnect()
        client.close()
    }

    @Test func `The messages end when the other side closes`() async throws {
        let (near, far) = try socketPair()
        let transport = MCPSocketTransport(descriptor: near)
        try await transport.connect()
        var messages = await transport.receive().makeAsyncIterator()

        try await far.write(Data("{\"last\":true}".utf8))
        far.close()
        // Een laatste regel zonder newline telt nog.
        #expect(try await messages.next() == Data(#"{"last":true}"#.utf8))
        #expect(try await messages.next() == nil)
        await transport.disconnect()
    }

    @Test func `Disconnecting ends the messages and closes the socket`() async throws {
        let (near, far) = try socketPair()
        let transport = MCPSocketTransport(descriptor: near)
        try await transport.connect()
        let client = LineClient(far)
        var messages = await transport.receive().makeAsyncIterator()

        await transport.disconnect()
        #expect(try await messages.next() == nil)
        #expect(await client.lines.next() == nil, "de andere kant ziet het einde")
        await #expect(throws: MCPSocketError.closed) { try await transport.send(Data("{}".utf8)) }
        client.close()
    }
}
