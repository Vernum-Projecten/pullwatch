import SwiftUI

/// Wie een push deed, in de tabel van Branches: de foto die de dienst bij de commit gaf, anders
/// het persoonssymbool, en de naam. Anders dan bij PR's en tags geen foto geraden uit de naam:
/// een naam uit git is geen login, dus `github.com/<naam>.png` kan van een ander zijn.
struct BranchAuthorLabel: View {
    let name: String
    let avatarURL: URL?

    var body: some View {
        HStack(spacing: 5) {
            PersonAvatar(url: avatarURL)
            Text(verbatim: name).lineLimit(1)
        }
    }
}
