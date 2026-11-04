public import Foundation

public struct JSONFileStore<Value: Codable & Sendable>: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Geeft `nil` als het bestand niet bestaat.
    public func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

public enum AppPaths {
    /// Launch-argument (`-PullwatchDataDirectory <map>`) waarmee de app met een eigen, lege
    /// datamap start: voor UI-tests, zodat die nooit de echte config en geschiedenis gebruiken.
    static let directoryOverrideKey = "PullwatchDataDirectory"

    public static func file(_ name: String, defaults: UserDefaults = .standard) -> URL {
        directory(defaults: defaults).appending(path: name)
    }

    public static func directory(defaults: UserDefaults = .standard) -> URL {
        if let override = defaults.string(forKey: directoryOverrideKey), !override.isEmpty {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory.appending(path: "Pullwatch")
    }
}
