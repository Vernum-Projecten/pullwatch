import PullwatchCore
import SwiftUI

/// Een keuze bij een nieuw account: de dienst, of het account op een eigen server staat, en bij
/// Gitea de smaak (Codeberg, Forgejo of Gitea). Dezelfde keuzes op de kaarten van het
/// welkomstvenster, in het toevoeg-menu van Instellingen en in de rondgang van de camera.
nonisolated struct AccountChoice: Hashable, Identifiable, Sendable {
    let kind: ProviderKind
    /// Een eigen server: GitHub Enterprise of een eigen GitLab-server. Bij Gitea zegt de smaak
    /// of er een server bij hoort.
    var enterprise = false
    /// Alleen bij Gitea.
    var flavour: GiteaFlavour?

    static let gitHub = AccountChoice(kind: .gitHub)
    static let gitHubEnterprise = AccountChoice(kind: .gitHub, enterprise: true)
    static let azureDevOps = AccountChoice(kind: .azureDevOps)
    static let gitLab = AccountChoice(kind: .gitLab)
    static let gitLabSelfManaged = AccountChoice(kind: .gitLab, enterprise: true)
    static let bitbucket = AccountChoice(kind: .bitbucket)
    static let codeberg = AccountChoice(kind: .gitea, flavour: .codeberg)
    static let forgejo = AccountChoice(kind: .gitea, flavour: .forgejo)
    static let gitea = AccountChoice(kind: .gitea, flavour: .gitea)

    /// Alle keuzes, in de volgorde van de kaarten.
    static let all: [AccountChoice] = [
        .gitHub, .gitHubEnterprise, .azureDevOps, .gitLab, .gitLabSelfManaged, .bitbucket, .codeberg, .forgejo, .gitea,
    ]

    /// Voor de bestandsnamen van de camera en als identiteit in een `ForEach`.
    var id: String {
        [kind.rawValue, enterprise ? "enterprise" : nil, flavour?.rawValue].compactMap { $0 }.joined(separator: "-")
    }

    /// De productnaam van de keuze, in elke taal hetzelfde.
    var title: String {
        switch (kind, enterprise) {
        case (.gitHub, true): "GitHub Enterprise"
        case (.gitLab, true): "GitLab Self-Managed"
        case (.bitbucket, _): "Bitbucket Cloud"
        default: flavour?.name ?? kind.name
        }
    }

    /// Het teken in het toevoeg-menu (een `NSImage`, dus op de main actor).
    @MainActor var menuIcon: Image {
        flavour.map { ProviderMark.menuIcon(for: $0) } ?? ProviderMark.menuIcon(for: kind)
    }
}
