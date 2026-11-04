import Foundation
import Testing

/// Controleert dat de test elke host in `expected` echt aanriep (anders toetst hij niets), en dat
/// elke aangeroepen host in het overzicht van Bronnen staat (`listed`).
package func expectCalledHostsAreListed(
    called: Set<String>, expected: [String], listed: Set<String>,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for host in expected {
        #expect(called.contains(host), "\(host) werd niet aangeroepen", sourceLocation: sourceLocation)
    }
    for host in called.sorted() {
        #expect(listed.contains(host), "\(host) wordt aangeroepen maar staat niet in het overzicht", sourceLocation: sourceLocation)
    }
}
