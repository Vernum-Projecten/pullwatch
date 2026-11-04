import Foundation

/// Wat een dienst over de gepubliceerde packages van één account zei (`PRProvider.publishedPackages`).
public enum PublishedPackages: Codable, Hashable, Sendable {
    /// De packages van de gevolgde repositories en de gevolgde eigenaren; leeg als er geen zijn.
    case packages([PublishedPackage])
    /// De dienst weigert het register te tonen: het token mist het recht (bij GitHub `read:packages`).
    /// `reason` zegt wat er nodig is, in de taal van de app op het moment van de check.
    case needsPermission(reason: String)
    /// Deze dienst (of deze server) kent geen register dat Pullwatch leest.
    case notSupported
    /// Netwerk, rate limit of een ander antwoord; de volgende check probeert het opnieuw.
    case failed(message: String)

    /// De packages; leeg bij elk ander resultaat.
    public var packages: [PublishedPackage] {
        if case .packages(let packages) = self { return packages }
        return []
    }

    private enum CodingKeys: String, CodingKey {
        case status, packages, reason, message
    }

    private enum Status: String, Codable {
        case packages, needsPermission, notSupported, failed
    }

    /// Een stand die Pullwatch niet kent (van een nieuwere versie) leest als `notSupported`, een
    /// package dat niet te lezen is valt weg: opgeslagen gegevens maken het rapport nooit onleesbaar.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try? c.decode(Status.self, forKey: .status) {
        case .packages:
            let items = (try? c.decodeIfPresent([Lossy<PublishedPackage>].self, forKey: .packages)) ?? []
            self = .packages(items.compactMap(\.value))
        case .needsPermission:
            self = .needsPermission(reason: (try? c.decodeIfPresent(String.self, forKey: .reason)) ?? "")
        case .failed:
            self = .failed(message: (try? c.decodeIfPresent(String.self, forKey: .message)) ?? "")
        case .notSupported, nil:
            self = .notSupported
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .packages(let packages):
            try c.encode(Status.packages, forKey: .status)
            try c.encode(packages, forKey: .packages)
        case .needsPermission(let reason):
            try c.encode(Status.needsPermission, forKey: .status)
            try c.encode(reason, forKey: .reason)
        case .notSupported:
            try c.encode(Status.notSupported, forKey: .status)
        case .failed(let message):
            try c.encode(Status.failed, forKey: .status)
            try c.encode(message, forKey: .message)
        }
    }
}
