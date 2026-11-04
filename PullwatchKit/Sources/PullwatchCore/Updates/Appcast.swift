public import Foundation

/// Eén update uit een Sparkle-appcast, zoals `generate_appcast` hem schrijft in de release-lane.
public struct AppcastItem: Equatable, Sendable {
    /// `sparkle:version`: het buildnummer (CFBundleVersion) van de update.
    public let build: String
    /// `sparkle:shortVersionString`: de versie (CFBundleShortVersionString); leeg als die ontbreekt.
    public let version: String
    /// `sparkle:channel`; nil is het standaardkanaal dat iedereen krijgt.
    let channel: String?
    /// `sparkle:minimumSystemVersion` ("26.6"); nil als de appcast er geen noemt.
    public let minimumSystemVersion: String?
    /// Het adres van de zip (`enclosure url`).
    let archiveURL: URL?

    public init(build: String, version: String, channel: String?, minimumSystemVersion: String?, archiveURL: URL?) {
        self.build = build
        self.version = version
        self.channel = channel
        self.minimumSystemVersion = minimumSystemVersion
        self.archiveURL = archiveURL
    }

    /// De tag van de release waar de zip bij hoort (`…/releases/download/<tag>/<zip>`), of nil.
    public var tag: String? {
        guard let parts = archiveURL?.pathComponents, let i = parts.lastIndex(of: "download"),
            i > 0, parts[i - 1] == "releases", parts.count == i + 3
        else { return nil }
        return parts[i + 1]
    }

    /// De releasepagina op GitHub (`…/releases/tag/<tag>`), of nil als de zip niet op GitHub staat.
    var releasePage: URL? {
        guard let archiveURL, let tag, var components = URLComponents(url: archiveURL, resolvingAgainstBaseURL: false)
        else { return nil }
        let parts = archiveURL.pathComponents
        guard let i = parts.lastIndex(of: "download") else { return nil }
        components.path = "/" + (parts[1..<i] + ["tag", tag]).joined(separator: "/")
        components.query = nil
        return components.url
    }

    /// De versie zoals een mens hem leest: de tag zonder "v" ("0.6.0-beta.1"), anders de versie.
    var displayVersion: String {
        if let tag, tag.hasPrefix("v") { return String(tag.dropFirst()) }
        return version.isEmpty ? build : version
    }
}

/// Leest een Sparkle-appcast en kiest de update die deze app mag installeren, met dezelfde regels
/// als Sparkle zelf: een hoger buildnummer, een kanaal dat de app toelaat en een macOS die
/// minstens het minimum van de update is.
enum Appcast {
    /// Alle items in de feed, in de volgorde van de feed. Onleesbare XML geeft een lege lijst.
    public static func items(_ data: Data) -> [AppcastItem] {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else { return [] }
        return reader.items
    }

    /// Het nieuwste item dat nieuwer is dan `build` (CFBundleVersion van deze app), uit het
    /// standaardkanaal of een van `channels`, en dat op `system` draait; nil als er geen is.
    public static func newest(
        in items: [AppcastItem],
        newerThan build: String,
        channels: Set<String>,
        system: OperatingSystemVersion
    ) -> AppcastItem? {
        items
            .filter { item in
                guard isNewer(item.build, than: build) else { return false }
                if let channel = item.channel, !channels.contains(channel) { return false }
                if let minimum = item.minimumSystemVersion, !runs(on: system, minimum: minimum) { return false }
                return true
            }
            .max { isNewer($1.build, than: $0.build) }
    }

    /// Vergelijkt buildnummers per getal ("10" na "9", "1.2.10" na "1.2.9"), zoals Sparkle's
    /// standaardvergelijking voor de nummers die Pullwatch gebruikt.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = numbers(candidate), b = numbers(current)
        guard !a.isEmpty else { return false }
        return Version.compare(a, b) == .orderedDescending
    }

    /// Of macOS `system` minstens `minimum` ("26.6", "26.6.1") is.
    public static func runs(on system: OperatingSystemVersion, minimum: String) -> Bool {
        let parts = numbers(minimum)
        let wanted = OperatingSystemVersion(
            majorVersion: parts.first ?? 0,
            minorVersion: parts.count > 1 ? parts[1] : 0,
            patchVersion: parts.count > 2 ? parts[2] : 0
        )
        return (system.majorVersion, system.minorVersion, system.patchVersion)
            >= (wanted.majorVersion, wanted.minorVersion, wanted.patchVersion)
    }

    private static func numbers(_ text: String) -> [Int] {
        text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").compactMap { Int($0) }
    }

    /// XMLParser-delegate: verzamelt per `<item>` de Sparkle-elementen en de enclosure.
    private final class Reader: NSObject, XMLParserDelegate {
        var items: [AppcastItem] = []
        private var current: [String: String]?
        private var text = ""

        func parser(
            _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
            qualifiedName: String?, attributes: [String: String] = [:]
        ) {
            text = ""
            if name == "item" {
                current = [:]
            } else if name == "enclosure", current != nil {
                current?["url"] = attributes["url"]
                // Oudere feeds zetten de versies als attribuut op de enclosure.
                for key in ["sparkle:version", "sparkle:shortVersionString"] where current?[key] == nil {
                    current?[key] = attributes[key]
                }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guard var item = current else { return }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "sparkle:version", "sparkle:shortVersionString", "sparkle:channel", "sparkle:minimumSystemVersion":
                if !value.isEmpty { item[name] = value }
                current = item
            case "item":
                if let build = item["sparkle:version"] {
                    items.append(
                        AppcastItem(
                            build: build,
                            version: item["sparkle:shortVersionString"] ?? "",
                            channel: item["sparkle:channel"],
                            minimumSystemVersion: item["sparkle:minimumSystemVersion"],
                            archiveURL: item["url"].flatMap(URL.init(string:))
                        ))
                }
                current = nil
            default:
                break
            }
            text = ""
        }
    }
}
