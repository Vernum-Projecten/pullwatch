import Foundation
import PullwatchCore
import Sparkle

/// Updates in de app met Sparkle 2, zoals FerroLICENCE (`App/Updater.swift`), maar eenvoudiger:
/// de releases van Pullwatch zijn openbaar, dus Sparkle leest de appcast en de zip rechtstreeks
/// van GitHub, zonder token.
///
/// Sparkle's eigen schema staat uit (`SUEnableAutomaticChecks` is NO in Info.plist): `AppModel`
/// kijkt eens per dag zelf in de appcast (`UpdateFeed`) en geeft Sparkle dan de feed. Sparkle
/// downloadt de zip, controleert eerst de EdDSA-handtekening (`SUVerifyUpdateBeforeExtraction`)
/// en daarna de Developer ID-handtekening, installeert en start opnieuw.
///
/// Zonder openbare sleutel in de build (`SPARKLE_PUBLIC_ED_KEY` leeg, zoals in een build uit de
/// broncode of de fork) start Sparkle niet en blijft de oude melding met de downloadknop.
final class Updater: NSObject, SPUUpdaterDelegate {
    /// De eigenaar van de releases op GitHub (`PW_RELEASES_OWNER`).
    let owner: String
    /// Sparkle kan updates controleren: de build heeft een geldige `SUPublicEDKey`.
    let isEnabled: Bool
    /// De appcast die Sparkle leest; `AppModel` zet hem bij elke check.
    var feedURL: URL?
    /// Testversies (het `beta`-kanaal) toelaten; volgt de instelling in `AppConfig`.
    var includeTestVersions = false

    private var controller: SPUStandardUpdaterController?

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        let owner = (info["PWReleasesOwner"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        self.owner = owner.isEmpty ? UpdateChecker.defaultOwner : owner
        isEnabled = UpdateFeed.isEnabled(publicKey: info["SUPublicEDKey"] as? String)
        super.init()
    }

    /// CFBundleVersion van deze build; Sparkle vergelijkt dat met `sparkle:version`.
    static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// Start Sparkle (eenmalig), alleen als updates in de app kunnen.
    func start() {
        guard isEnabled, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        controller.startUpdater()
        self.controller = controller
    }

    /// Updates op de achtergrond downloaden en bij het afsluiten installeren. Sparkle bewaart
    /// dit zelf in de defaults van de app (`SUAutomaticallyUpdate`).
    var installsAutomatically: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { controller?.updater.automaticallyDownloadsUpdates = newValue }
    }

    /// Sparkle's venster: de release notes, Installeren, en na de installatie opnieuw starten.
    func installNow() {
        controller?.checkForUpdates(nil)
    }

    /// Stil downloaden; Sparkle installeert bij het afsluiten van Pullwatch.
    func downloadInBackground() {
        controller?.updater.checkForUpdatesInBackground()
    }

    // MARK: SPUUpdaterDelegate (Sparkle roept die op de main actor aan)

    func feedURLString(for updater: SPUUpdater) -> String? {
        (feedURL ?? UpdateFeed.latestURL(owner: owner)).absoluteString
    }

    /// Een testversie staat op het `beta`-kanaal; Sparkle biedt hem alleen aan als
    /// "Testversies aanbieden" aan staat.
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UpdateFeed.channels(includeTestVersions: includeTestVersions)
    }
}
