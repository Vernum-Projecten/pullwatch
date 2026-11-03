import PullwatchCore
import SwiftUI

/// De auteur van een PR met wie er meewerkte: kleine gestapelde foto's en "mona en 2 anderen".
/// De tooltip en VoiceOver noemen iedereen bij naam. Zonder co-auteurs alleen de auteur, met
/// `avatarURL` (de maker van een tag of release) met zijn foto ervoor.
struct ContributorsLabel: View {
    let author: String
    let coAuthors: [Person]
    let kind: ProviderKind
    var avatarURL: URL? = nil

    /// Hooguit zoveel foto's; de tekst noemt het aantal.
    private let maxAvatars = 3

    var body: some View {
        if coAuthors.isEmpty, let avatarURL {
            HStack(spacing: 5) {
                PersonAvatar(url: avatarURL)
                Text(verbatim: author).lineLimit(1)
            }
        } else if coAuthors.isEmpty {
            Text(verbatim: author).lineLimit(1)
        } else {
            HStack(spacing: 5) {
                HStack(spacing: -6) {
                    PersonAvatar(url: kind == .gitHub ? Account.gitHubAvatarURL(author, size: 40) : nil)
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

    /// "ana, mona en Jan": iedereen, de auteur eerst.
    private var names: String {
        ([author] + coAuthors.map(\.handle)).formatted(.list(type: .and))
    }

    private func avatarURL(_ person: Person) -> URL? {
        person.avatarURL ?? person.login.flatMap { kind == .gitHub ? Account.gitHubAvatarURL($0, size: 40) : nil }
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
        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
        .accessibilityHidden(true)
    }
}
