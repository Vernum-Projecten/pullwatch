import Darwin

/// Wat er mis kan gaan met de socket tussen de helper en de app.
public enum MCPSocketError: Error, Sendable, Equatable, CustomStringConvertible {
    /// Een systeemaanroep faalde, met zijn `errno`.
    case system(String, Int32)
    /// Het pad past niet in een `sockaddr_un` (104 bytes).
    case pathTooLong(String)
    /// Er luistert al een andere Pullwatch op dit pad.
    case inUse(String)
    /// De descriptor is al gesloten.
    case closed

    public var description: String {
        switch self {
        case .system(let call, let code):
            "\(call) failed: \(String(cString: strerror(code)))"
        case .pathTooLong(let path):
            "socket path is too long: \(path)"
        case .inUse(let path):
            "another Pullwatch already listens on \(path)"
        case .closed:
            "the connection is closed"
        }
    }
}
