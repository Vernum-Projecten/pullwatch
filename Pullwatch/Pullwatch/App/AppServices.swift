import Foundation
import PullwatchCore
import PullwatchGitHub
import PullwatchProviders

/// Wat de modellen gebruiken maar geen view leest: de bestanden, de Keychain, de poll-engine, de
/// meldingen en het netwerk. Eén keer gemaakt door `AppModel`, en niet `@Observable`: niets
/// hierin hoort een view opnieuw te laten tekenen.
final class AppServices {
    let configStore = JSONFileStore<AppConfig>(url: AppPaths.file("config.json"))
    let historyStore = JSONFileStore<History>(url: AppPaths.file("history.json"))
    let legacyRecentStore = JSONFileStore<RecentList>(url: AppPaths.file("recent.json"))
    let versionStore = JSONFileStore<VersionReport>(url: AppPaths.file("versions.json"))
    let versionHistoryStore = JSONFileStore<VersionHistory>(url: AppPaths.file("version-history.json"))
    let secrets = SecretStores.shared
    let engine = PollEngine(
        makeProvider: { ProviderFactory.make($0, http: AppModel.networking) },
        store: JSONFileStore<SeenState>(url: AppPaths.file("seen.json"))
    )
    let notifier = Notifier.shared
    /// De Pullwatch GitHub App uit de xcconfig; niet ingesteld = geen "Inloggen met GitHub".
    let gitHubApp = GitHubAppConfig.main

    var http: any HTTPClient { AppModel.networking }

    /// Een provider voor een account, via het netwerk van de app.
    func provider(for account: Account, pat: String? = nil) -> any PRProvider {
        ProviderFactory.make(account, pat: pat, secrets: secrets, http: http, gitHubApp: gitHubApp)
    }

    /// Een versiecheck via het netwerk van de app, met de metadata en de eigen packages uit het
    /// vorige rapport. Bronnen in `disabledSources` (Instellingen, Bronnen) vraagt hij niets.
    func versionChecker(previous: VersionReport?, disabledSources: Set<DataSourceID>, accounts: [Account]) -> VersionChecker {
        VersionChecker(
            makeProvider: { ProviderFactory.make($0, http: AppModel.networking) }, http: AppModel.networking,
            metadataCache: previous?.packageMetadata ?? [:], disabledSources: disabledSources,
            publishedPackages: previous?.publishedPackages ?? [], accounts: accounts
        )
    }
}
