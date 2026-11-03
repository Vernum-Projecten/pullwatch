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
        .overlay { Circle().strokeBorder(.separator, lineWidth: 0.5) }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var placeholder: some View {
        if kind.glyphKeepsItsColours {
            // Het GitHub-logo zoals GitHub het geeft (zwart of wit), met wat ruimte in de cirkel.
            ProviderMark(kind: kind, size: size * 0.62)
                .frame(width: size, height: size)
                .background(.quaternary)
        } else {
            Image(systemName: Self.placeholderSymbol(for: kind))
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    /// Het symbool zonder foto voor diensten die geen logo in een app toestaan (zie
    /// `ProviderKind.glyph`): Azure DevOps een wolk, GitLab een groep, want daar volgt een
    /// GitLab-account meestal.
    static func placeholderSymbol(for kind: ProviderKind) -> String {
        switch kind {
        case .gitHub: "person.crop.circle.fill"
        case .azureDevOps: "cloud.circle.fill"
        case .gitLab: "person.2.circle.fill"
        }
    }
}
