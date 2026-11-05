package import Foundation

private let logger = Log(category: "Paging")

/// De ene regel voor het volgen van een link naar de volgende pagina (een `Link`-header met
/// `rel="next"`, of een `next` in de JSON): alleen naar dezelfde oorsprong als de API van het
/// account (https, dezelfde host en dezelfde poort). Een link naar een andere host, een ander
/// schema of een andere poort volgt geen enkele provider: daar stopt het bladeren, met een
/// logregel, en gaat er geen verzoek (en dus geen token) heen. Elke provider bladert hiermee.
package enum PageLink {
    /// De URL met `rel="next"` uit een `Link`-header (RFC 8288):
    /// `<https://api.github.com/…&after=…>; rel="next", <…>; rel="last"`.
    package static func next(inHeader header: String) -> URL? {
        for part in header.split(separator: ",") {
            let pieces = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let target = pieces.first, target.hasPrefix("<"), target.hasSuffix(">"),
                  pieces.dropFirst().contains(where: { $0.replacingOccurrences(of: " ", with: "") == #"rel="next""# }) else { continue }
            return URL(string: String(target.dropFirst().dropLast()))
        }
        return nil
    }

    /// De `next` uit de `Link`-header van `response`.
    package static func next(in response: HTTPURLResponse) -> URL? {
        response.value(forHTTPHeaderField: "Link").flatMap(next(inHeader:))
    }

    /// Ligt `url` op dezelfde oorsprong als `base`: https, dezelfde host (hoofdletterongevoelig)
    /// en dezelfde poort? Het pad telt niet: GitHub Enterprise Server heeft zijn API op
    /// `<server>/api/v3`, een link mag overal op die host wijzen.
    package static func isSameOrigin(_ url: URL, as base: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", base.scheme?.lowercased() == "https",
              let host = url.host()?.lowercased(), host == base.host()?.lowercased() else { return false }
        return url.port == base.port
    }

    /// De volgende pagina na `current`, als die te volgen is: op dezelfde oorsprong als `api` en
    /// niet `current` zelf (anders bladert het rond). Een link elders geeft nil en een logregel
    /// met alleen de host, nooit de query.
    package static func follow(_ candidate: URL?, after current: URL, api: URL) -> URL? {
        guard let candidate, candidate != current else { return nil }
        guard isSameOrigin(candidate, as: api) else {
            logger.warning("next-link naar \(candidate.scheme ?? "?")://\(candidate.host() ?? "?")\(candidate.port.map { ":\($0)" } ?? "") niet gevolgd: niet de API op \(api.host() ?? "?"); bladeren gestopt")
            return nil
        }
        return candidate
    }
}
