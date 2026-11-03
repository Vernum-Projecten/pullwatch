import Foundation

/// Leest `Co-authored-by: Naam <e-mail>`-regels uit commitberichten en maakt van commit-auteurs
/// en trailers de lijst co-auteurs van een PR: ontdubbeld op e-mailadres (en login), zonder de
/// auteur van de PR en zonder bots.
public enum CoAuthorTrailer {
    /// Eén regel, hoofdletterongevoelig op de sleutel; nil als de regel geen geldige trailer is.
    public static func parse(line: String) -> Person? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.firstIndex(of: ":"),
              trimmed[..<colon].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("co-authored-by") == .orderedSame
        else { return nil }
        let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard let open = value.lastIndex(of: "<"), let close = value.lastIndex(of: ">"), open < close else { return nil }
        let name = value[..<open].trimmingCharacters(in: .whitespaces)
        let email = value[value.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, email.contains("@"), !email.contains(where: \.isWhitespace) else { return nil }
        return Person(name: name, login: noreplyLogin(email), email: email)
    }

    /// Alle trailers in één commitbericht, in volgorde.
    public static func people(in message: String) -> [Person] {
        message.split(whereSeparator: \.isNewline).compactMap { parse(line: String($0)) }
    }

    /// Ontdubbelt `candidates` (op e-mailadres, dan login, hoofdletterongevoelig; een kandidaat met
    /// login of foto vult een eerdere zonder aan), en laat bots en de auteur weg. `author` zijn de
    /// namen, logins en e-mailadressen waaronder de auteur van de PR bekend is.
    public static func coAuthors(from candidates: [Person], author: [String]) -> [Person] {
        let authorKeys = Set(author.map { $0.lowercased() }.filter { !$0.isEmpty })
        var result: [Person] = []
        for candidate in candidates {
            guard !isBot(candidate) else { continue }
            let keys = identityKeys(candidate)
            guard keys.union([candidate.name.lowercased()]).isDisjoint(with: authorKeys) else { continue }
            if let index = result.firstIndex(where: { !identityKeys($0).isDisjoint(with: keys) }) {
                var known = result[index]
                known.login = known.login ?? candidate.login
                known.email = known.email ?? candidate.email
                known.avatarURL = known.avatarURL ?? candidate.avatarURL
                result[index] = known
            } else {
                result.append(candidate)
            }
        }
        return result
    }

    /// GitHub-bots heten "naam[bot]", ook in hun noreply-adres.
    public static func isBot(_ person: Person) -> Bool {
        [person.name, person.login ?? "", person.email ?? ""].contains { $0.localizedCaseInsensitiveContains("[bot]") }
    }

    /// E-mailadres en login waarmee twee vermeldingen dezelfde persoon zijn; zonder beide de naam.
    private static func identityKeys(_ person: Person) -> Set<String> {
        var keys: Set<String> = []
        if let email = person.email?.lowercased(), !email.isEmpty { keys.insert(email) }
        if let login = (person.login ?? person.email.flatMap(noreplyLogin))?.lowercased() { keys.insert(login) }
        return keys.isEmpty ? [person.name.lowercased()] : keys
    }

    /// `12345+octo@users.noreply.github.com` en `octo@users.noreply.github.com` horen bij `octo`.
    static func noreplyLogin(_ email: String) -> String? {
        let suffix = "@users.noreply.github.com"
        guard email.lowercased().hasSuffix(suffix) else { return nil }
        let local = email.dropLast(suffix.count)
        let login = local.split(separator: "+", maxSplits: 1).last.map(String.init) ?? ""
        return login.isEmpty ? nil : login
    }
}
