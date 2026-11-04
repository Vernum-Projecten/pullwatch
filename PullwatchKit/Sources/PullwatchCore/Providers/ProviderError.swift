import Foundation

public enum ProviderError: Error, Equatable, Sendable {
    case unauthorized
    case rateLimited(until: Date)
    case server(status: Int)
    case network(String)
    case decoding(String)
    case cliNotFound(String)
    case cliNotLoggedIn(String)
    case missingToken
    case noAccess(String)
    /// Een CLI (`gh`, `az`, `glab`) of een server gaf binnen de tijd geen antwoord. `command`
    /// is de naam van het programma of de host van de server.
    case timeout(command: String)

    public var userMessage: String {
        userMessage(bundle: .localizedCore)
    }

    /// De tekst in de taal van `bundle`, zodat tests elke taal kunnen controleren.
    func userMessage(bundle: Bundle) -> String {
        switch self {
        case .unauthorized:
            return String(localized: "Token ongeldig of verlopen", bundle: bundle)
        case .rateLimited(let until):
            return String(localized: "Rate limit, opnieuw om \(until.formatted(date: .omitted, time: .shortened))", bundle: bundle)
        case .server(let status):
            return String(localized: "Serverfout (\(status))", bundle: bundle)
        case .network(let message):
            return String(localized: "Netwerkfout: \(message)", bundle: bundle)
        case .decoding(let message):
            return String(localized: "Onverwacht antwoord: \(message)", bundle: bundle)
        case .cliNotFound(let name):
            return String(localized: "\(name) niet gevonden (installeer via Homebrew)", bundle: bundle)
        case .cliNotLoggedIn(let name):
            let command = switch name {
            case "az": "az login"
            case "glab": "glab auth login"
            default: "gh auth login"
            }
            return String(localized: "Niet ingelogd, voer `\(command)` uit", bundle: bundle)
        case .missingToken:
            return String(localized: "Geen token ingesteld", bundle: bundle)
        case .noAccess(let name):
            return String(localized: "Geen toegang tot \"\(name)\", controleer de naam", bundle: bundle)
        case .timeout(let command):
            return String(localized: "\(command) reageert niet op tijd", bundle: bundle, comment: "Naam van een programma (gh, az, glab) of een server")
        }
    }
}
