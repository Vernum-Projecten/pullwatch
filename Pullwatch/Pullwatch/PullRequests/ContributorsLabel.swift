import PullwatchCore
import SwiftUI

/// De auteur van een PR met wie er meewerkte: kleine gestapelde foto's en "mona en 2 anderen".
/// De tooltip en VoiceOver noemen iedereen bij naam. De foto van de auteur is `avatarURL` (zoals
/// de provider hem gaf, voor een PR of een tag), anders zijn GitHub-foto als dat te raden is.
struct ContributorsLabel: View {
    let author: String
    let coAuthors: [Person]
    let kind: ProviderKind
    /// De server van het account (GitHub Enterprise), voor de foto's; nil = github.com.
    var web: URL? = nil
    /// De foto van de auteur van de API; nil = raden (`Account.authorAvatarURL`).
    var avatarURL: URL? = nil

    /// Hooguit zoveel foto's; de tekst noemt het aantal.
    private let maxAvatars = 3

    var body: some View {
        if coAuthors.isEmpty {
            // Ook één auteur krijgt een foto, zoals bij tags: zo staan de namen in de kolom
            // recht onder elkaar. Zonder foto (Azure DevOps, of een naam zonder GitHub-account)
            // het persoonssymbool.
            HStack(spacing: 5) {
                PersonAvatar(url: authorAvatarURL)
                Text(verbatim: author).lineLimit(1)
            }
        } else {
            HStack(spacing: 5) {
                HStack(spacing: -6) {
                    PersonAvatar(url: authorAvatarURL)
                    ForEach(Array(coAuthors.prefix(maxAvatars - 1).enumerated()), id: \.offset) { _, person in
                        PersonAvatar(url: avatarURL(person))
                    }
                }
                Text("\(author) en \(coAuthors.count) anderen", comment: "Auteur van de PR, aantal co-auteurs")
                    .lineLimit(1)
            }
            .help(Text(verbatim: names))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: names))
        }
    }

    /// De foto van de API, anders de gok op GitHub; een bot (`github-actions[bot]`) zonder foto
    /// van de API krijgt het persoonssymbool, want zijn `/<naam>.png` bestaat niet.
    private var authorAvatarURL: URL? {
        Account.authorAvatarURL(avatarURL, login: author, kind: kind, size: 40, web: web)
    }

    /// "ana, mona en Jan": iedereen, de auteur eerst.
    private var names: String {
        ([author] + coAuthors.map(\.handle)).formatted(.list(type: .and))
    }

    private func avatarURL(_ person: Person) -> URL? {
        // Zelfde keuze als voor de auteur: de foto van de API, anders de gok (niet voor een bot).
        person.login.map { Account.authorAvatarURL(person.avatarURL, login: $0, kind: kind, size: 40, web: web) } ?? person.avatarURL
    }
}
