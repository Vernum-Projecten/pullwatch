import Foundation
import PullwatchCore
import PullwatchGitHub
import PullwatchProviders

/// Wat de modellen gebruiken maar geen view leest: de bestanden, de Keychain, de poll-engine, de
/// meldingen en het netwerk. Eén keer gemaakt door `AppModel`, en niet `@Observable`: niets
/// hierin hoort een view opnieuw te laten tekenen.
final class AppServices {
    let configStore: JSONFileStore<AppConfig>
    let historyStore: JSONFileStore<History>
    let branchStore: JSONFileStore<BranchLog>
    let legacyRecentStore: JSONFileStore<RecentList>
    let versionStore: JSONFileStore<VersionReport>
    let versionHistoryStore: JSONFileStore<VersionHistory>
    let secrets = SecretStores.shared
    let engine: PollEngine
    let notifier = Notifier.shared
    /// De Pullwatch GitHub App uit de xcconfig; niet ingesteld = geen "Inloggen met GitHub".
    let gitHubApp = GitHubAppConfig.main

    /// `defaults` bepaalt de datamap (`-PullwatchDataDirectory`, `AppPaths`); een test geeft een
    /// eigen suite mee, zodat hij de instellingen van de app niet aanraakt.
    init(defaults: UserDefaults = .standard) {
        func file(_ name: String) -> URL { AppPaths.file(name, defaults: defaults) }
        configStore = JSONFileStore(url: file("config.json"))
        historyStore = JSONFileStore(url: file("history.json"))
        branchStore = JSONFileStore(url: file("branches.json"))
        legacyRecentStore = JSONFileStore(url: file("recent.json"))
        versionStore = JSONFileStore(url: file("versions.json"))
        versionHistoryStore = JSONFileStore(url: file("version-history.json"))
        engine = PollEngine(
            makeProvider: { ProviderFactory.make($0, http: AppModel.networking) },
            store: JSONFileStore<SeenState>(url: file("seen.json"))
        )
    }

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
