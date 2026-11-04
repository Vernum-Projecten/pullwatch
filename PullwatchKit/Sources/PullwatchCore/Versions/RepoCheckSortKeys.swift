import Foundation

// De sorteersleutels van de tabellen op de repo-pagina.

/// Een versienummer om op te sorteren: op getallen, zodat 4.17.9 vóór 4.17.15 komt. Zonder
/// versie achteraan. De getallen worden één keer gelezen, zodat sorteren snel blijft.
public struct VersionSortKey: Comparable, Hashable, Sendable {
    public let text: String?
    private let parts: [Int]

    public init(_ text: String?) {
        self.text = text
        self.parts = text.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
    }

    public static func < (lhs: VersionSortKey, rhs: VersionSortKey) -> Bool {
        switch (lhs.text, rhs.text) {
        case (.some, .some): Version.compare(lhs.parts, rhs.parts) == .orderedAscending
        case (.some, nil): true
        case (nil, _): false
        }
    }
}

/// Een tekst om op te sorteren, zonder hoofdletters en met een gewone vergelijking: een
/// `String` in een `KeyPathComparator` vergelijkt per taal, en dat is bij duizenden rijen traag.
public struct TextSortKey: Comparable, Hashable, Sendable {
    public let text: String

    public init(_ text: String) {
        self.text = text.lowercased()
    }

    public static func < (lhs: TextSortKey, rhs: TextSortKey) -> Bool { lhs.text < rhs.text }
}
