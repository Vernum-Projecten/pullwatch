import PullwatchCore
import SwiftUI

/// Profielfoto van een GitHub-gebruiker of -organisatie, rond, zoals de accounts in RustRover.
/// Zonder foto (Azure DevOps, nog geen eigenaar, offline) het symbool van de dienst.
struct AccountAvatar: View {
    let url: URL?
    let kind: ProviderKind
    var size: CGFloat = 24

    init(account: Account, size: CGFloat = 24) {
        url = account.avatarURL
        kind = account.kind
        self.size = size
    }

    init(gitHubLogin login: String, size: CGFloat = 24) {
        url = Account.gitHubAvatarURL(login)
        kind = .gitHub
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
        .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: kind == .gitHub ? "person.crop.circle.fill" : "cloud.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
    }
}
