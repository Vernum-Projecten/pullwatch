import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Het overzicht van alle bronnen en verbindingen als tekst (Kopieer overzicht), en de controle
/// dat elke host die Pullwatch aanroept in dat overzicht staat.
@Suite struct SourcesOverviewTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)
    let dutch = Locale(identifier: "nl_NL")

    func text(_ config: AppConfig = AppConfig()) -> String {
        SourcesOverview.text(config: config, appVersion: "0.5.0", date: now, locale: dutch)
    }

    @Test func overviewListsEverySource() {
        let text = text()
        for source in DataSource.all {
            let name = source.name(bundle: SourcesOverview.bundle(for: dutch))
            #expect(text.contains("- \(name): aan."), "\(name) ontbreekt")
            for endpoint in source.endpoints {
                #expect(text.contains(endpoint.absoluteString))
            }
        }
        #expect(text.hasPrefix("Pullwatch 0.5.0: bronnen ("))
        for header in ["Kwetsbaarheden", "Versies", "Overige verbindingen"] {
            #expect(text.contains("\n\(header)\n"), "kop \(header) ontbreekt")
        }
    }

    @Test func `The CI checks are a source of their own under Pull requests`() {
        let on = text()
        let off = text(AppConfig(disabledSources: [.ciChecks]))
        #expect(on.contains("\nPull requests\n- CI-checks: aan."))
        #expect(off.contains("\nPull requests\n- CI-checks: uit."))
        #expect(DataSource.source(.ciChecks).group == .pullRequests)
    }

    @Test func overviewShowsOnAndOff() {
        let text = text(AppConfig(disabledSources: [.npm]))
        #expect(text.contains("- npm: uit."))
        #expect(text.contains("- PyPI: aan."))
    }

    @Test func overviewListsAccountServers() throws {
        let enterprise = Account(
            kind: .gitHub, organization: "acme", authMethod: .pat, instanceURL: URL(string: "https://ghe.example.com")
        )
        let config = AppConfig(accounts: [enterprise])

        let text = text(config)

        let line = try #require(text.split(separator: "\n").first { $0.contains(enterprise.displayName) })
        #expect(line.contains("https://ghe.example.com"))
        #expect(line.contains(": aan."))
        #expect(SourcesOverview.otherConnections(config: config, locale: dutch).contains { $0.urls.contains { $0.host() == "ghe.example.com" } })
    }

    @Test func accountServerIsTheAddressTheProviderCalls() {
        func server(_ kind: ProviderKind, _ instance: String? = nil) -> String {
            let account = Account(kind: kind, organization: "acme", authMethod: .pat, instanceURL: instance.flatMap(URL.init(string:)))
            return SourcesOverview.server(of: account).absoluteString
        }
        #expect(server(.gitHub) == "https://api.github.com")
        #expect(server(.gitHub, "https://github.com") == "https://api.github.com")
        #expect(server(.gitHub, "https://acme.ghe.com") == "https://api.acme.ghe.com")
        #expect(server(.gitHub, "https://ghe.example.com") == "https://ghe.example.com/api/v3")
        #expect(server(.azureDevOps) == "https://dev.azure.com/acme")
        #expect(server(.gitLab) == "https://gitlab.com/api/v4")
        #expect(server(.gitLab, "https://git.example.com") == "https://git.example.com/api/v4")
        // Een adres met "/" aan het eind geeft geen dubbele "/".
        #expect(server(.gitLab, "https://git.example.com/") == "https://git.example.com/api/v4")
        #expect(server(.gitHub, "https://ghe.example.com/") == "https://ghe.example.com/api/v3")
    }

    @Test func pausedAccountAndUpdateCheckShowTheirState() {
        let paused = Account(kind: .azureDevOps, organization: "acme", authMethod: .pat, isPaused: true)
        let config = AppConfig(accounts: [paused], checkForUpdates: false)

        let text = text(config)

        #expect(text.contains("- \(paused.displayName): uit."))
        #expect(text.contains("https://dev.azure.com/acme"))
        let updates = text.split(separator: "\n").filter { $0.contains("Updatecheck van Pullwatch") }
        #expect(updates.count == 1, "de updatecheck is één regel met al zijn adressen")
        #expect(updates.allSatisfy { $0.contains(": uit.") && $0.contains("https://api.github.com") && $0.contains("https://github.com") })
        let connections = SourcesOverview.otherConnections(config: config, locale: dutch)
        // GitHub stuurt de appcast en de zip van een release door naar de hosts van de downloads.
        #expect(connections.map { $0.urls.map { $0.host() } } == [
            ["dev.azure.com"],
            ["api.github.com", "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"],
        ])
        #expect(connections.last?.detail.contains("Automatisch op updates controleren staat uit") == true)
    }

    @Test func gitHubSignInAndProfilePicturesAreListed() throws {
        let app = Account(kind: .gitHub, organization: "octo", authMethod: .gitHubApp)
        let enterprise = Account(kind: .gitHub, organization: "acme", authMethod: .pat, instanceURL: URL(string: "https://ghe.example.com"))
        let config = AppConfig(accounts: [app, enterprise])

        let connections = SourcesOverview.otherConnections(config: config, locale: dutch)

        let signIn = try #require(connections.first { $0.name == "Inloggen bij GitHub" })
        #expect(signIn.urls.map(\.absoluteString) == ["https://github.com"])
        let pictures = try #require(connections.first { $0.name == "Profielfoto's" })
        #expect(pictures.urls.map(\.absoluteString) == ["https://github.com", "https://avatars.githubusercontent.com", "https://ghe.example.com",
                                                        "https://avatars.ghe.example.com"])
        let text = text(config)
        #expect(text.contains("- Inloggen bij GitHub: aan."))
        #expect(text.contains("- Profielfoto's: aan."))
    }

    @Test func signInAndPicturesFollowTheAccounts() {
        // Zonder GitHub-account geen van beide; met alleen een uitgezet account staan ze uit.
        let azure = Account(kind: .azureDevOps, organization: "acme", authMethod: .pat)
        let none = SourcesOverview.otherConnections(config: AppConfig(accounts: [azure]), locale: dutch).map(\.name)
        #expect(!none.contains("Inloggen bij GitHub") && !none.contains("Profielfoto's"))

        let token = Account(kind: .gitHub, organization: "octo", authMethod: .pat)
        let withToken = SourcesOverview.otherConnections(config: AppConfig(accounts: [token]), locale: dutch).map(\.name)
        #expect(!withToken.contains("Inloggen bij GitHub"), "met een token logt Pullwatch niet in via GitHub")
        #expect(withToken.contains("Profielfoto's"))

        let paused = Account(kind: .gitHub, organization: "octo", authMethod: .gitHubApp, isPaused: true)
        let text = text(AppConfig(accounts: [paused]))
        #expect(text.contains("- Inloggen bij GitHub: uit."))
        #expect(text.contains("- Profielfoto's: uit."))
    }

    @Test func pictureHostsPerKindOfAccount() {
        func hosts(_ kind: ProviderKind, _ instance: String? = nil) -> [String] {
            let account = Account(kind: kind, organization: "acme", authMethod: .pat, instanceURL: instance.flatMap(URL.init(string:)))
            return SourcesOverview.pictureHosts(of: account).map(\.absoluteString)
        }
        #expect(hosts(.gitHub) == ["https://github.com", "https://avatars.githubusercontent.com"])
        // Een Enterprise-server met subdomain isolation zet de foto's op avatars.<server>.
        #expect(hosts(.gitHub, "https://ghe.example.com") == ["https://ghe.example.com", "https://avatars.ghe.example.com"])
        #expect(hosts(.gitHub, "https://git.example.com:8443") == ["https://git.example.com:8443", "https://avatars.git.example.com:8443"])
        #expect(hosts(.gitHub, "https://acme.ghe.com") == ["https://acme.ghe.com", "https://avatars.acme.ghe.com"])
        #expect(hosts(.gitLab) == ["https://gitlab.com", "https://secure.gravatar.com"])
        #expect(hosts(.gitLab, "https://git.example.com/gitlab") == ["https://git.example.com/gitlab", "https://secure.gravatar.com"])
        #expect(hosts(.azureDevOps).isEmpty)
    }

    @Test func gitLabAccountHasProfilePictures() throws {
        let gitLab = Account(kind: .gitLab, organization: "acme", authMethod: .pat)
        let connections = SourcesOverview.otherConnections(config: AppConfig(accounts: [gitLab]), locale: dutch)
        let pictures = try #require(connections.first { $0.name == "Profielfoto's" })
        #expect(pictures.urls.compactMap { $0.host() } == ["gitlab.com", "secure.gravatar.com"])
        #expect(!connections.contains { $0.name == "Inloggen bij GitHub" })
    }

    /// Een account via `az` of `gh`: het overzicht zegt dat dat programma zelf een server kan aanroepen.
    @Test func cliAccountsNameWhatTheCLICalls() throws {
        let azure = Account(kind: .azureDevOps, organization: "acme", authMethod: .cli)
        let gitHub = Account(kind: .gitHub, organization: "octo", authMethod: .cli)
        let token = Account(kind: .gitHub, organization: "pat", authMethod: .pat)
        let text = text(AppConfig(accounts: [azure, gitHub, token]))
        let lines = text.split(separator: "\n")
        let azureLine = try #require(lines.first { $0.contains(azure.displayName) })
        #expect(azureLine.contains("Azure CLI (az)") && azureLine.contains("login.microsoftonline.com"))
        let gitHubLine = try #require(lines.first { $0.contains(gitHub.displayName) })
        #expect(gitHubLine.contains("GitHub CLI (gh)") && gitHubLine.contains("api.github.com"))
        let tokenLine = try #require(lines.first { $0.contains(token.displayName) })
        #expect(!tokenLine.contains("CLI"))

        let english = SourcesOverview.text(config: AppConfig(accounts: [azure]), appVersion: "0.5.0", date: now, locale: Locale(identifier: "en_GB"))
        #expect(english.contains("Azure CLI (az)") && !english.contains("het token"))
    }

    /// Een naam die geen eigennaam is staat in de taal van het overzicht; een eigennaam niet.
    @Test func sourceNamesFollowTheLanguage() {
        let english = SourcesOverview.text(config: AppConfig(), appVersion: "0.5.0", date: now, locale: Locale(identifier: "en_GB"))
        #expect(english.contains("- GitHub security: on."))
        #expect(english.contains("- Go module proxy: on."))
        #expect(english.contains("- OSV.dev: on."))
        #expect(!english.contains("GitHub-beveiliging") && !english.contains("Go-moduleproxy"))
        let german = SourcesOverview.text(config: AppConfig(), appVersion: "0.5.0", date: now, locale: Locale(identifier: "de_DE"))
        #expect(!german.contains("GitHub-beveiliging") && !german.contains("Go-moduleproxy"))
        let dutch = text()
        #expect(dutch.contains("- GitHub-beveiliging: aan."))
        #expect(dutch.contains("- Go-moduleproxy: aan."))
    }

    @Test func textHasNoSeparatorsOrDashes() {
        let text = text(AppConfig(accounts: [Account(kind: .gitHub, organization: "acme", authMethod: .pat)]))
        #expect(!text.contains("·"))
        #expect(!text.contains("—"))
    }

    @Test func titleHasVersionAndDateInTheLocale() {
        // 3 november 2026, 12:00 UTC: in elke tijdzone van Europa dezelfde dag.
        let date = Date(timeIntervalSince1970: 1_793_707_200)
        let dutch = SourcesOverview.text(config: AppConfig(), appVersion: "0.5.0", date: date, locale: dutch)
        #expect(dutch.hasPrefix("Pullwatch 0.5.0: bronnen (3 november 2026)\n\nKwetsbaarheden\n- OSV.dev: aan."))
        let english = SourcesOverview.text(config: AppConfig(), appVersion: "0.5.0", date: date, locale: Locale(identifier: "en_GB"))
        #expect(english.contains("3 November 2026"))
        #expect(english.contains("- npm: on."))
    }

    /// Een volledige check (registries, OSV, endoflife.date en de GitHub Advisory Database)
    /// tegen een mock: elke host die daarbij de deur uit gaat moet in het overzicht staan.
    @Test func everyHostIsInTheOverview() async throws {
        let http = MockHTTPClient()
        http.on("querybatch", body: #"{"results":[{},{"vulns":[{"id":"GHSA-jf85-cpcp-j695"}]},{}]}"#)
        http.on("vulns/GHSA-jf85-cpcp-j695", body: #"{"id":"GHSA-jf85-cpcp-j695","aliases":["CVE-2019-10744"],"affected":[{"package":{"name":"requests","ecosystem":"PyPI"},"ranges":[{"events":[{"fixed":"2.32.0"}]}]}]}"#)
        http.on("advisories", body: AdvisoryDatabaseTests.advisoryJSON)
        http.on("registry.npmjs.org/left-pad", body: #"{"name":"left-pad","dist-tags":{"latest":"1.3.0"},"versions":{"1.3.0":{"name":"left-pad","version":"1.3.0"}}}"#)
        http.on("pypi.org/pypi/requests", body: #"{"info":{"name":"requests","version":"2.32.0"},"releases":{"2.31.0":[],"2.32.0":[]}}"#)
        http.on("proxy.golang.org/x.com/y/@latest", body: #"{"Version":"v1.1.0"}"#)
        http.on("products/go", body: DataSourceCheckTests.goReleases)
        var files = DataSourceCheckTests.npmAndPyPI
        files["go.mod"] = DataSourceCheckTests.gomod
        let provider = FileProvider(repos: ["acme/a"], files: ["acme/a": files])
        let account = Account(kind: .gitHub, organization: "acme", authMethod: .pat, repoWatch: ["acme/a": .prs])
        let config = AppConfig(accounts: [account])
        let checker = VersionChecker(makeProvider: { _ in provider }, http: http, now: { now })

        let report = await checker.run(accounts: config.accounts)
        _ = await checker.completingAdvisories(of: report, accounts: config.accounts)

        let called = Set(http.requests.compactMap { $0.url?.host() })
        let listed = Set(DataSource.all.flatMap(\.endpoints).compactMap { $0.host() })
            .union(SourcesOverview.otherConnections(config: config, locale: dutch).flatMap(\.urls).compactMap { $0.host() })
        // Zonder deze hosts toetst de test niets: ze horen bij de check zelf.
        expectCalledHostsAreListed(
            called: called,
            expected: ["api.osv.dev", "registry.npmjs.org", "pypi.org", "proxy.golang.org", "endoflife.date", "api.github.com"],
            listed: listed
        )
    }
}
