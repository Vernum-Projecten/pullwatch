import PullwatchCore
import SwiftUI

/// Profielfoto van een GitHub-gebruiker of -organisatie, rond, zoals de accounts in RustRover.
/// Zonder foto (Azure DevOps, GitLab, Gitea, nog geen eigenaar, offline) het teken van de dienst.
struct AccountAvatar: View {
    let url: URL?
    let glyph: Glyph
    let glyphScale: CGFloat
    var size: CGFloat = 24

    init(account: Account, size: CGFloat = 24) {
        url = account.avatarURL
        glyph = account.glyph
        glyphScale = account.glyphScale
        self.size = size
    }

    init(gitHubLogin login: String, size: CGFloat = 24) {
        url = Account.gitHubAvatarURL(login)
        glyph = ProviderKind.gitHub.glyph
        glyphScale = ProviderKind.gitHub.glyphScale
        self.size = size
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay { Circle().strokeBorder(.separator, lineWidth: 0.5) }
        .accessibilityHidden(true)
    }

    /// Zonder foto het teken van de dienst (`ProviderMark`), met wat ruimte in de cirkel: overal
    /// hetzelfde teken als op de keuzekaarten en in het toevoeg-menu.
    private var placeholder: some View {
        ProviderMark(glyph: glyph, scale: glyphScale, size: size * 0.62)
            .frame(width: size, height: size)
            .background(.quaternary)
    }
}
