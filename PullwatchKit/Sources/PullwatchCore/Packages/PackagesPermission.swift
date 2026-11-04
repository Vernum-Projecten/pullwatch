import Foundation

/// Wat er nodig is als een dienst zonder eigen String Catalog (GitLab, Azure DevOps) zijn register
/// weigert: de reden van `PublishedPackages.needsPermission`, in de taal van de app.
package enum PackagesPermission {
    /// GitLab leest het pakketregister en de container registry met de scope `read_api`.
    package static var gitLabReadAPI: String {
        String(
            localized: "Het register van GitLab is alleen te lezen met de scope read_api: gebruik een persoonlijk token met read_api, of log opnieuw in met de GitLab CLI (glab auth login).",
            bundle: .localizedCore,
            comment: "Reden waarom de packages van een GitLab-account niet te lezen zijn; read_api en de glab-opdracht niet vertalen"
        )
    }

    /// Azure Artifacts leest de feeds met het recht Packaging (Read) van een PAT; met `az` mist
    /// het account zelf leesrecht op de feeds.
    package static func azurePackagingRead(for authMethod: AuthMethod) -> String {
        switch authMethod {
        case .pat, .gitHubApp:
            String(
                localized: "De feeds van Azure Artifacts zijn alleen te lezen met het recht Packaging (Read): geef je persoonlijke token dat recht, of gebruik de Azure CLI (az login).",
                bundle: .localizedCore,
                comment: "Reden waarom de packages van een Azure DevOps-account met een PAT niet te lezen zijn; Packaging (Read) is de naam van het recht bij Azure DevOps, niet vertalen"
            )
        case .cli:
            String(
                localized: "Je account mag de feeds van Azure Artifacts niet lezen: vraag de beheerder van de feed om de rol Feed Reader, of gebruik een persoonlijk token met Packaging (Read).",
                bundle: .localizedCore,
                comment: "Reden waarom de packages van een Azure DevOps-account via de Azure CLI niet te lezen zijn; Feed Reader en Packaging (Read) zijn namen bij Azure DevOps, niet vertalen"
            )
        }
    }
}
