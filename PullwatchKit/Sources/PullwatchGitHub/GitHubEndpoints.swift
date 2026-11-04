public import Foundation

/// Waar een GitHub-account zijn webpagina's, REST-API en GraphQL-API heeft, afgeleid van het
/// adres van de server (`Account.instanceURL`):
///
/// - github.com (of geen adres): `https://github.com`, `https://api.github.com` en
///   `https://api.github.com/graphql`, precies zoals altijd.
/// - GitHub Enterprise Cloud met data residency (`<naam>.ghe.com`): de API op
///   `https://api.<naam>.ghe.com`, GraphQL op `https://api.<naam>.ghe.com/graphql`.
/// - GitHub Enterprise Server (elk ander adres): REST op `<server>/api/v3`, GraphQL op
///   `<server>/api/graphql`.
public struct GitHubEndpoints: Sendable, Equatable {
    enum Flavor: Sendable, Equatable {
        case dotCom, dataResidency, server
    }

    let flavor: Flavor
    /// De webpagina's: repo's, PR's, releases, installaties.
    let web: URL
    /// De REST-API, zonder "/" aan het eind.
    let api: URL
    let graphQL: URL

    public init(instanceURL: URL?) {
        let host = instanceURL?.host()?.lowercased()
        if let instanceURL, let host, host != "github.com" {
            let labels = host.split(separator: ".")
            if labels.count == 3, host.hasSuffix(".ghe.com") {
                // Eén eigen subdomein: acme.ghe.com, met de API op api.acme.ghe.com.
                flavor = .dataResidency
                web = URL(string: "https://\(host)")!
                api = URL(string: "https://api.\(host)")!
                graphQL = api.appending(path: "graphql")
            } else {
                flavor = .server
                web = instanceURL
                api = URL(string: instanceURL.absoluteString + "/api/v3")!
                graphQL = URL(string: instanceURL.absoluteString + "/api/graphql")!
            }
        } else {
            flavor = .dotCom
            web = URL(string: "https://github.com")!
            api = URL(string: "https://api.github.com")!
            graphQL = api.appending(path: "graphql")
        }
    }

    var isDotCom: Bool { flavor == .dotCom }

    /// De host voor `gh auth token --hostname`: "github.com", "acme.ghe.com" of de server.
    /// Een poort hoort erbij ("github.example.com:8443"), zoals `gh` de host zelf noemt.
    public var cliHost: String {
        let host = web.host() ?? "github.com"
        return web.port.map { "\(host):\($0)" } ?? host
    }
}
