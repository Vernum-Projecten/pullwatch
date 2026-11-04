import Foundation
import Observation
import PullwatchCore

/// De vensters van de app, met hun scene-id.
enum WindowID: String {
    case main, onboarding
    /// Het Instellingen-venster (de Settings-scene, geopend met `openSettings`).
    case settings
    /// Het Over-venster.
    case about
    /// Erkenningen: de licenties van de open-sourcesoftware in de app.
    case acknowledgements
}

/// Een verzoek om een venster te openen; elk verzoek is nieuw, ook voor hetzelfde venster.
struct WindowRequest: Equatable {
    let window: WindowID
    let id = UUID()
}

/// Waar de app staat: welk venster open moet, het gekozen onderdeel in de zijbalk, de pagina's
/// erop en de filters die een sprong vanaf een andere plek meegeeft.
@Observable
final class AppRouter {
    /// Een venster dat open moet, als gegeven: `WindowOpener` (in het menubalk-label, dat er
    /// altijd is) opent het met `openWindow` en zet dit weer op nil.
    var windowRequest: WindowRequest?

    /// Gekozen onderdeel of project in de zijbalk. Het hoofdvenster onthoudt het onderdeel zelf
    /// (`@SceneStorage`) en zet het hier bij openen, als er nog niets gekozen is.
    var sidebarSelection: SidebarItem? {
        didSet {
            // Zelf iets anders kiezen begint bovenaan dat onderdeel, zonder filters van elders.
            if !isNavigating, oldValue != sidebarSelection {
                path = []
                historyTokens = []
            }
        }
    }

    /// Pagina's op de `NavigationStack` van het zichtbare onderdeel (repo-pagina, statistieken van
    /// een repo); leeg toont de lijst van het onderdeel.
    var path: [Route] = []
    /// Auteur- en repofilters op PR's of Tags vanaf een andere plek; tokens in het zoekveld.
    var historyTokens: [HistoryToken] = []
    /// Zoektekst die het onderdeel Versies bij openen overneemt (sprong vanaf een CVE).
    var packagesSearch: String?
    /// Filter dat het onderdeel Packages bij openen overneemt (een repo vanaf zijn Overzicht, een
    /// package vanaf een melding); het onderdeel zet dit weer op nil.
    var publishedPackagesRequest: PublishedPackagesRequest?
    /// Het laatst gekozen tabblad van de repo-pagina; geldt voor elke repo.
    var repoTab: RepoTab = UserDefaults.standard.string(forKey: "repoTab").flatMap(RepoTab.init) ?? .overview {
        didSet { UserDefaults.standard.set(repoTab.rawValue, forKey: "repoTab") }
    }
    /// Een rij die de repo-pagina bij openen kiest, met het inspectievenster open.
    var repoSelectionRequest: RepoSelectionRequest?
    /// Of "Volg een repository…" open moet in het hoofdvenster (menu Archief, knoppenbalk van Repo's).
    var isWatchingRepository = false
    /// Of de accounts in Instellingen de keuze voor een nieuw account moeten tonen (Nieuw account…
    /// in het menu Archief); die zet dit weer op false.
    var addsAccount = false
    /// Het tabblad van Instellingen; het venster bindt zijn tabbladen hieraan. Het blijft staan
    /// waar de persoon het liet, tot iets om een tabblad vraagt (`showSettings(_:)`).
    var settingsTab: SettingsTab = AppRouter.initialSettingsTab
    /// Tijdens een sprong naar een ander onderdeel blijven pad en filters van die sprong staan.
    @ObservationIgnored private var isNavigating = false

    /// Onderdeel van het hoofdvenster; een gekozen project hoort bij PR's, Tags of Repo's.
    var mainSection: MainSection { sidebarSelection?.section ?? .pullRequests }

    /// Opent een venster (en haalt de app naar voren).
    func show(_ window: WindowID) {
        windowRequest = WindowRequest(window: window)
    }

    /// Opent Instellingen op een tabblad. `show(.settings)` opent het op het laatst gekozen tabblad.
    func showSettings(_ tab: SettingsTab) {
        settingsTab = tab
        show(.settings)
    }

    /// Het tabblad waarmee Instellingen de eerste keer opent.
    private static var initialSettingsTab: SettingsTab {
        #if DEBUG
        // Voor schermafbeeldingen: `-PullwatchSettingsPane agents`.
        UserDefaults.standard.string(forKey: "PullwatchSettingsPane").flatMap(SettingsTab.init) ?? .accounts
        #else
        .accounts
        #endif
    }

    /// Opent een onderdeel vanaf een andere plek (menu, melding, sprong): bovenaan, zonder filters.
    func navigate(to section: MainSection) {
        isNavigating = true
        sidebarSelection = .section(section)
        path = []
        historyTokens = []
        isNavigating = false
    }

    /// Opent het hoofdvenster op een onderdeel.
    func show(_ section: MainSection) {
        navigate(to: section)
        show(.main)
    }

    /// Opent de pagina van een repo bovenop het zichtbare onderdeel, zodat terug weer daar uitkomt.
    func showRepo(id: String) {
        if sidebarSelection == nil { navigate(to: .repos) }
        guard path.last != .repo(id) else { return }
        path.append(.repo(id))
    }

    /// PR's of Tags, gefilterd op auteur en/of repo.
    func showHistory(_ kind: ItemKind, author: String? = nil, repo: HistoryRepo? = nil) {
        navigate(to: kind == .pullRequest ? .pullRequests : .tags)
        historyTokens = [author.map(HistoryToken.author), repo.map(HistoryToken.repo)].compactMap(\.self)
    }

    /// Versies, gezocht op een package.
    func showPackage(_ name: String) {
        navigate(to: .dependencies)
        packagesSearch = name
    }

    /// Packages, gefilterd op wat één repo publiceert.
    func showPublishedPackages(of repo: HistoryRepo) {
        navigate(to: .packages)
        publishedPackagesRequest = PublishedPackagesRequest(repo: repo)
    }

    /// Packages, gezocht op een package (vanaf een melding).
    func showPublishedPackage(_ name: String) {
        navigate(to: .packages)
        publishedPackagesRequest = PublishedPackagesRequest(search: name)
    }

    /// Statistieken van één repo, bovenop de repo-pagina.
    func showStats(repoId: String) {
        path.append(.stats(repoId: repoId))
    }

    /// ⌘N: Instellingen met de keuze voor een nieuw account.
    func addAccount() {
        addsAccount = true
        showSettings(.accounts)
    }

    /// ⌘[ in het menu Ga: één pagina terug op de stack van het zichtbare onderdeel.
    func goBack() {
        if !path.isEmpty { path.removeLast() }
    }
}
