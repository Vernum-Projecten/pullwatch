/// Welke versies van een package Pullwatch bewaart: één regel voor elk register (#229). Een
/// register geeft de versies nieuwste of hoogste eerst; Pullwatch houdt er hooguit
/// `recentVersionLimit` van, maar altijd met de hoogste stabiele release erbij. Zonder die regel
/// valt een stabiele release achter meer dan tien nieuwere pre-releases weg voordat
/// `releasedVersion` hem kan kiezen, en wordt een pre-release de nieuwste versie.
extension PublishedPackage {
    /// De eerste `recentVersionLimit` van `items`, in hun volgorde. Staat de hoogste stabiele
    /// release (op versievolgorde, over alle `items`) daar niet bij, dan neemt hij de plaats van de
    /// laatste in. Een versie die niet als versie leest, telt niet als stabiele release.
    package static func recentVersions<Item>(_ items: [Item], version: (Item) -> String) -> [Item] {
        var recent = Array(items.prefix(recentVersionLimit))
        guard items.count > recent.count, !recent.isEmpty else { return recent }
        let stable = items
            .compactMap { item in Version(version(item)).map { (item: item, version: $0) } }
            .filter { !$0.version.isPrerelease }
            .max { $0.version < $1.version }
        if let stable, !recent.contains(where: { version($0) == version(stable.item) }) {
            recent[recent.count - 1] = stable.item
        }
        return recent
    }
}
