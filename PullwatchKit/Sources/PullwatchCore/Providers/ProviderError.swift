public import Foundation

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
    /// Het token werkt, maar mist een scope die dit verzoek nodig heeft (Gitea en Forgejo zeggen
    /// welke, bv. "read:issue").
    case missingScope(String)
    /// De server heeft een certificaat dat macOS niet vertrouwt (zelfondertekend, verlopen, of
    /// van een eigen CA die niet in de sleutelhanger staat). De host van de server.
    case untrustedCertificate(String)
    /// Op dit adres antwoordt geen server van de verwachte dienst (bv. een webpagina in plaats
    /// van de API). De host en de dienst ("Forgejo").
    case unexpectedServer(host: String, service: String)
    /// Het account heeft geen bruikbaar adres voor zijn eigen server (`Account.serverProblem`):
    /// er ging geen verzoek uit. De productnaam ("Forgejo") en wat er schort.
    case unusableServer(service: String, problem: Account.ServerProblem)
    /// Een Bitbucket-account zonder het e-mailadres van het Atlassian-account (`Account.lacksEmail`):
    /// er ging geen verzoek uit.
    case missingEmail

    public var userMessage: String {
        userMessage(bundle: .localizedCore)
    }

    /// De tekst in de taal van `bundle`, zodat tests elke taal kunnen controleren.
    package func userMessage(bundle: Bundle) -> String {
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
        case .missingScope(let scope):
            return String(localized: "Het token mist de scope \(scope); maak een token met de scopes die Pullwatch noemt", bundle: bundle, comment: "Scope van een token, bv. read:issue")
        case .untrustedCertificate(let host):
            return String(localized: "Het certificaat van \(host) wordt niet vertrouwd; Pullwatch praat alleen met servers met een geldig https-certificaat", bundle: bundle, comment: "Host van de server")
        case .unexpectedServer(let host, let service):
            return String(localized: "Op \(host) draait geen \(service); controleer het adres van de server", bundle: bundle, comment: "Host, dienst (Gitea, Forgejo, Codeberg)")
        case .unusableServer(let service, .missing):
            return String(localized: "Het adres van de \(service)-server ontbreekt", bundle: bundle, comment: "Dienst (Forgejo, Gitea, GitLab, GitHub); het account wordt niet opgehaald")
        case .unusableServer(_, .invalid(let text)):
            return String(localized: "Het serveradres \(text) is geen geldig https-adres", bundle: bundle, comment: "Het adres zoals het in de instellingen staat; het account wordt niet opgehaald")
        case .missingEmail:
            return String(localized: "Het e-mailadres van het Atlassian-account ontbreekt", bundle: bundle, comment: "Bitbucket wil het e-mailadres samen met het API-token; het account wordt niet opgehaald")
        }
    }
}
