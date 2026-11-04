import Foundation
import Testing
@testable import PullwatchMCP

/// Het knippen van de bytestroom in berichten, zoals de stdio-transport van MCP.
@Suite struct LineFramerTests {
    private func message(_ text: String) -> LineFramer.Line {
        .message(Data(text.utf8))
    }

    @Test func `A whole line is one message`() {
        var framer = LineFramer(maxLineBytes: 100)
        #expect(framer.append(Data("{\"a\":1}\n".utf8)) == [message("{\"a\":1}")])
    }

    @Test func `A line split over chunks comes out once it is complete`() {
        var framer = LineFramer(maxLineBytes: 100)
        #expect(framer.append(Data("{\"a\"".utf8)).isEmpty)
        #expect(framer.append(Data(":1".utf8)).isEmpty)
        #expect(framer.append(Data("}\n".utf8)) == [message("{\"a\":1}")])
    }

    @Test func `Lines joined in one chunk come out separately and in order`() {
        var framer = LineFramer(maxLineBytes: 100)
        #expect(framer.append(Data("one\ntwo\nthr".utf8)) == [message("one"), message("two")])
        #expect(framer.append(Data("ee\n".utf8)) == [message("three")])
    }

    @Test func `Empty lines and a carriage return are not part of a message`() {
        var framer = LineFramer(maxLineBytes: 100)
        #expect(framer.append(Data("\n\none\r\n\n".utf8)) == [message("one")])
    }

    @Test func `A line over the limit is reported once and skipped to its end`() {
        var framer = LineFramer(maxLineBytes: 10)
        #expect(framer.append(Data("0123456789AB".utf8)) == [.oversized])
        #expect(framer.append(Data(String(repeating: "x", count: 1000).utf8)).isEmpty)
        #expect(framer.append(Data("tail\nnext\n".utf8)) == [message("next")])
    }

    @Test func `A line over the limit inside one chunk does not hide the next`() {
        var framer = LineFramer(maxLineBytes: 4)
        #expect(framer.append(Data("toolong\nok\n".utf8)) == [.oversized, message("ok")])
    }

    @Test func `A line of exactly the limit passes`() {
        var framer = LineFramer(maxLineBytes: 4)
        #expect(framer.append(Data("abcd\n".utf8)) == [message("abcd")])
    }

    @Test func `The last line without a newline comes out at the end`() {
        var framer = LineFramer(maxLineBytes: 100)
        #expect(framer.append(Data("one\ntwo".utf8)) == [message("one")])
        #expect(framer.finish() == [message("two")])
    }

    @Test func `The rest of a skipped line is not a message at the end`() {
        var framer = LineFramer(maxLineBytes: 2)
        #expect(framer.append(Data("abc".utf8)) == [.oversized])
        #expect(framer.finish().isEmpty)
    }
}
