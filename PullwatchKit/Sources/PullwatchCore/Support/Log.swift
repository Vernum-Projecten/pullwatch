import Foundation
import os

/// Logniveaus zoals overal gebruikelijk (syslog), van veel naar weinig. Ingesteld onder
/// Instellingen → Algemeen; alles vanaf dat niveau gaat naar het systeemlog (Console.app,
/// subsystem `nl.torrisi.pullwatch`).
public enum LogLevel: Int, CaseIterable, Comparable, Identifiable, Sendable {
    case debug, info, notice, warning, error, critical

    public var id: Int { rawValue }

    /// De standaardnaam, in elke taal hetzelfde.
    public var name: String {
        switch self {
        case .debug: "Debug"
        case .info: "Info"
        case .notice: "Notice"
        case .warning: "Warning"
        case .error: "Error"
        case .critical: "Critical"
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Zonder eigen keuze: alles in debug-builds, vanaf Notice in een release.
    public static var standard: LogLevel {
        #if DEBUG
        .debug
        #else
        .notice
        #endif
    }
}

/// Loggen per onderdeel naar het systeemlog, met het ingestelde minimumniveau. Nooit tokens,
/// wachtwoorden of codes loggen; repo-, account- en loginnamen mogen (het is een ontwikkelaarstool).
public struct Log: Sendable {
    static let subsystem = "nl.torrisi.pullwatch"
    static let levelKey = "logLevel"

    /// Het minimumniveau uit de instellingen.
    public static var minimum: LogLevel {
        get {
            (UserDefaults.standard.object(forKey: levelKey) as? Int).flatMap(LogLevel.init(rawValue:)) ?? .standard
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: levelKey) }
    }

    private let logger: Logger

    public init(category: String) {
        logger = Logger(subsystem: Self.subsystem, category: category)
    }

    public func debug(_ message: @autoclosure () -> String) { write(.debug, message) }
    public func info(_ message: @autoclosure () -> String) { write(.info, message) }
    public func notice(_ message: @autoclosure () -> String) { write(.notice, message) }
    public func warning(_ message: @autoclosure () -> String) { write(.warning, message) }
    public func error(_ message: @autoclosure () -> String) { write(.error, message) }
    public func critical(_ message: @autoclosure () -> String) { write(.critical, message) }

    private func write(_ level: LogLevel, _ message: () -> String) {
        guard level >= Self.minimum else { return }
        let text = message()
        switch level {
        case .debug: logger.debug("\(text, privacy: .public)")
        case .info: logger.info("\(text, privacy: .public)")
        case .notice: logger.notice("\(text, privacy: .public)")
        case .warning: logger.warning("\(text, privacy: .public)")
        case .error: logger.error("\(text, privacy: .public)")
        case .critical: logger.critical("\(text, privacy: .public)")
        }
    }
}
