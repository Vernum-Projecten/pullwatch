import Foundation

/// Een zoektekst die een pull request bij zijn nummer noemt: `1570`, `#1570`, `!42`,
/// `FerroFED#1570`, `FerroFED #1570` of `FerroHEALTH/FerroFED#1570`. Met een teken telt alleen
/// een PR van een dienst die dat teken schrijft (`ProviderKind.pullRequestPrefix`); met een repo
/// ervoor alleen een PR van een repo met die naam, voluit of het laatste deel ervan.
public struct PullRequestNumberQuery: Hashable, Sendable {
    /// Wat voor het teken staat; nil zonder repo.
    public let repo: String?
    /// `#` of `!`; nil bij alleen cijfers.
    public let prefix: String?
    public let number: Int

    /// Nil als de tekst geen nummer noemt.
    public init?(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits: Substring
        if let mark = text.lastIndex(where: { $0 == "#" || $0 == "!" }) {
            digits = text[text.index(after: mark)...]
            prefix = String(text[mark])
            let before = text[..<mark].trimmingCharacters(in: .whitespaces)
            repo = before.isEmpty ? nil : before
        } else {
            digits = Substring(text)
            prefix = nil
            repo = nil
        }
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(digits), number > 0 else {
            return nil
        }
        self.number = number
    }

    /// Of `pr` de bedoelde PR is. `kind` is de dienst van zijn account; zonder dienst telt het
    /// teken niet.
    public func matches(_ pr: PullRequest, kind: ProviderKind?) -> Bool {
        guard pr.number == number else { return false }
        if let prefix, let kind, kind.pullRequestPrefix != prefix { return false }
        guard let repo else { return true }
        return pr.repo.caseInsensitiveCompare(repo) == .orderedSame
            || pr.repo.lowercased().hasSuffix("/" + repo.lowercased())
    }
}
