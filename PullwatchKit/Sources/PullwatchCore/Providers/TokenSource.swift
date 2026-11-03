import Foundation

public protocol TokenSource: Sendable {
    func token() async throws -> String
    func invalidate() async
}

extension TokenSource {
    public func invalidate() async {}
}

public struct StaticTokenSource: TokenSource {
    private let value: String

    public init(token: String) {
        self.value = token
    }

    public func token() async throws -> String { value }
}
