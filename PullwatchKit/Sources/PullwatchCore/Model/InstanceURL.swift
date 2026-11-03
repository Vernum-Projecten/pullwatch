import Foundation

/// Het adres van een eigen server (GitLab self-managed, later GitHub Enterprise), zoals iemand
/// het intypt: met of zonder `https://`, eventueel met een pad ("https://example.com/gitlab").
/// Het token gaat naar dit adres, dus alleen https, met een host, zonder inloggegevens, query of
/// fragment.
public enum InstanceURL {
    /// Het genormaliseerde adres (kleine letters in de host, zonder "/" aan het eind), of nil als
    /// de tekst geen bruikbaar https-adres is. Een tekst zonder schema krijgt `https://`.
    public static func parse(_ text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: \.isWhitespace) else { return nil }
        if !value.contains("://") { value = "https://" + value }
        guard var components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty, host.contains("."),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        components.scheme = "https"
        components.host = host.lowercased()
        while components.path.hasSuffix("/") { components.path.removeLast() }
        // "/api/v4" hoort niet bij het adres van de server; de provider zet het er zelf achter.
        if components.path.lowercased().hasSuffix("/api/v4") { components.path.removeLast("/api/v4".count) }
        return components.url
    }
}
