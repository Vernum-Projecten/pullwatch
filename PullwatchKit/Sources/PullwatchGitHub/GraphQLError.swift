import Foundation

/// Een fout uit een GraphQL-antwoord; `extensions.code` noemt een veld dat de server niet kent.
struct GraphQLError: Decodable {
    struct Extensions: Decodable {
        let code: String?
    }

    /// Een stap in `path`: een veld of alias, of een plek in een lijst.
    enum PathComponent: Decodable, Equatable {
        case key(String)
        case index(Int)

        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let index = try? c.decode(Int.self) { self = .index(index) } else { self = .key(try c.decode(String.self)) }
        }
    }

    let type: String?
    let message: String?
    let extensions: Extensions?
    /// Waar in het antwoord de fout zit, bv. `["pr0", "pullRequest", "headCommit"]`.
    let path: [PathComponent]?

    /// Geen recht op dit veld: de GitHub App of het token mag het niet lezen.
    var isForbidden: Bool {
        type == "FORBIDDEN" || message?.contains("Resource not accessible by") == true
    }
}

/// De server kent een veld of argument uit de vraag niet: een GitHub Enterprise Server die ouder
/// is dan github.com. Wat Pullwatch dan nog kan lezen, leest het op een andere manier.
struct GraphQLSchemaMismatch: Error {
    static let codes: Set<String> = [
        "undefinedField", "undefinedType", "argumentNotAccepted", "argumentLiteralsIncompatible",
    ]

    static func matches(_ errors: [GraphQLError]?) -> Bool {
        guard let errors, !errors.isEmpty else { return false }
        return errors.contains { error in
            error.extensions?.code.map(codes.contains) == true
                || error.message?.contains("doesn't exist on type") == true
                || error.message?.contains("doesn't accept argument") == true
        }
    }
}
