import PullwatchCore
import SwiftUI

/// De auteur van een PR met wie er meewerkte: kleine gestapelde foto's en "mona en 2 anderen".
/// De tooltip en VoiceOver noemen iedereen bij naam. Zonder co-auteurs de auteur met zijn foto
/// ervoor: `avatarURL` (de maker van een tag of release) of zijn GitHub-foto.
struct ContributorsLabel: View {
    let author: String
    let coAuthors: [Person]
    let kind: ProviderKind
    /// De server van het account (GitHub Enterprise), voor de foto's; nil = github.com.
    var web: URL? = nil
    var avatarURL: URL? = nil

    /// Hooguit zoveel foto's; de tekst noemt het aantal.
    private let maxAvatars = 3

    var body: some View {
        if coAuthors.isEmpty {
            // Ook één auteur krijgt een foto, zoals bij tags: zo staan de namen in de kolom
            // recht onder elkaar. Zonder foto (Azure DevOps, of een naam zonder GitHub-account)
            // het persoonssymbool.
            HStack(spacing: 5) {
                PersonAvatar(url: avatarURL ?? authorAvatarURL)
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

    /// De foto van de auteur op GitHub, alleen voor iets dat een login kan zijn (geen spaties).
    /// Een bot (`dependabot[bot]`) heeft zijn foto onder de naam zonder `[bot]`.
    private var authorAvatarURL: URL? {
        guard !author.contains(" ") else { return nil }
        let login = author.hasSuffix("[bot]") ? String(author.dropLast("[bot]".count)) : author
        return Account.gitHubAvatarURL(login, kind: kind, size: 40, web: web)
    }

    /// "ana, mona en Jan": iedereen, de auteur eerst.
    private var names: String {
        ([author] + coAuthors.map(\.handle)).formatted(.list(type: .and))
    }

    private func avatarURL(_ person: Person) -> URL? {
        person.avatarURL ?? person.login.flatMap { Account.gitHubAvatarURL($0, kind: kind, size: 40, web: web) }
    }
}

/// Een kleine ronde foto met een rand in de achtergrondkleur, zodat de foto's in een stapel
/// los van elkaar te zien zijn. Zonder foto het persoonssymbool.
private struct PersonAvatar: View {
    let url: URL?
    var size: CGFloat = 16

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(.background, in: .circle)
        .clipShape(.circle)
        .overlay { Circle().strokeBorder(.background, lineWidth: 1.5) }
        .accessibilityHidden(true)
    }
}
