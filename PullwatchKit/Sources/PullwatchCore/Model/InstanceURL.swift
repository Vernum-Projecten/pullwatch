public import Foundation

/// Het adres van een eigen server (GitLab self-managed, GitHub Enterprise), zoals iemand
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

    /// Als `parse(_:)`, met wat iemand van de API van de dienst plakt teruggebracht tot het adres
    /// van de webpagina's. GitHub: "https://github.example.com/api/v3" en ".../api/graphql" worden
    /// "https://github.example.com", "api.acme.ghe.com" wordt "acme.ghe.com" en "api.github.com"
    /// wordt "github.com".
    public static func parse(_ text: String, for kind: ProviderKind) -> URL? {
        guard let url = parse(text) else { return nil }
        guard kind == .gitHub, var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host else { return url }
        for suffix in ["/api/v3", "/api/graphql"] where components.path.lowercased().hasSuffix(suffix) {
            components.path.removeLast(suffix.count)
        }
        if host == "api.github.com" || (host.hasPrefix("api.") && host.hasSuffix(".ghe.com")) {
            components.host = String(host.dropFirst("api.".count))
        }
        return components.url ?? url
    }
}
