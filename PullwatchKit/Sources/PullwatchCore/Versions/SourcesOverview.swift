import Foundation

/// Alles waar Pullwatch mee praat, als platte tekst voor **Kopieer overzicht** (te plakken in een
/// mail of Teams-bericht, leesbaar als Markdown), en de verbindingen buiten de catalogus van
/// bronnen: de servers van de accounts en de updatecheck.
public enum SourcesOverview {
    /// Het overzicht: een kop met versie en datum, dan Kwetsbaarheden, Versies en Overige
    /// verbindingen, met per regel `- naam: aan|uit. beschrijving. adres`.
    ///
    /// `locale` bepaalt de datum en de taal van de teksten (de `.lproj` van die taal in de bundle
    /// van PullwatchCore; een taal die de app niet heeft valt terug op die van de app). De naam
    /// van een account (`Account.displayName`) staat altijd in de taal van de app.
    public static func text(config: AppConfig, appVersion: String, date: Date, locale: Locale = .current) -> String {
        let bundle = bundle(for: locale)
        let day = date.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: locale))
        var lines = [String(localized: "Pullwatch \(appVersion): bronnen (\(day))", bundle: bundle, locale: locale,
                            comment: "Kop van het gekopieerde overzicht van bronnen: versie, datum")]

        func section(_ title: String, _ rows: [Row]) {
            lines.append("")
            lines.append(title)
            lines += rows.map { $0.line(bundle: bundle, locale: locale) }
        }

        func sources(_ group: DataSourceGroup) -> [Row] {
            DataSource.all.filter { $0.group == group }.map { source in
                Row(name: source.name, isOn: config.isEnabled(source.id),
                    summary: resolve(source.summary, bundle: bundle, locale: locale), urls: source.endpoints)
            }
        }

        section(String(localized: "Kwetsbaarheden", bundle: bundle, locale: locale, comment: "Groep van bronnen"), sources(.vulnerabilities))
        section(String(localized: "Versies", bundle: bundle, locale: locale, comment: "Groep van bronnen"), sources(.versions))
        section(String(localized: "Overige verbindingen", bundle: bundle, locale: locale, comment: "Groep: servers van accounts en de updatecheck"),
                connections(config: config, bundle: bundle, locale: locale).map(\.row))
        return lines.joined(separator: "\n") + "\n"
    }

    /// De verbindingen buiten `DataSource.all`, één rij per verbinding (in de tekst en op het
    /// tabblad): per account de server waar de provider van dat account echt mee praat; inloggen
    /// bij GitHub (als een account via de GitHub App inlogt); de profielfoto's (als er een
    /// GitHub-account is); en de updatecheck op `api.github.com` en `github.com`. De `detail`
    /// noemt ook de stand: een uitgezet account, en of "Automatisch op updates controleren" aan staat.
    public static func otherConnections(config: AppConfig, locale: Locale = .current) -> [(name: String, urls: [URL], detail: String)] {
        connections(config: config, bundle: bundle(for: locale), locale: locale).map { ($0.row.name, $0.row.urls, $0.detail) }
    }

    /// Het adres waar de provider van `account` echt mee praat, zoals de providers het opbouwen:
    /// GitHub zoals `GitHubEndpoints.api` (github.com via `api.github.com`, GHE.com via
    /// `api.<naam>.ghe.com`, een Enterprise-server via `<server>/api/v3`), Azure DevOps
    /// `dev.azure.com/<organisatie>`, GitLab `<server>/api/v4`.
    public static func server(of account: Account) -> URL {
        let instance = account.effectiveInstanceURL
        switch account.kind {
        case .azureDevOps:
            let base = URL(string: "https://dev.azure.com")!
            return account.organization.isEmpty ? base : base.appending(path: account.organization)
        case .gitHub:
            guard let instance, let host = instance.host()?.lowercased(), host != "github.com" else {
                return URL(string: "https://api.github.com")!
            }
            if host.split(separator: ".").count == 3, host.hasSuffix(".ghe.com") {
                return URL(string: "https://api.\(host)")!
            }
            return instance.appending(path: "api/v3")
        case .gitLab:
            return (instance ?? URL(string: "https://gitlab.com")!).appending(path: "api/v4")
        }
    }

    // MARK: - Opbouw

    /// Eén regel van het overzicht.
    private struct Row {
        let name: String
        let isOn: Bool
        let summary: String
        let urls: [URL]

        func line(bundle: Bundle, locale: Locale) -> String {
            let address = urls.map(\.absoluteString).formatted(.list(type: .and).locale(locale))
            return isOn
                ? String(localized: "- \(name): aan. \(summary). \(address)", bundle: bundle, locale: locale,
                         comment: "Regel in het gekopieerde overzicht: naam, beschrijving, adres(sen); de bron staat aan")
                : String(localized: "- \(name): uit. \(summary). \(address)", bundle: bundle, locale: locale,
                         comment: "Regel in het gekopieerde overzicht: naam, beschrijving, adres(sen); de bron staat uit")
        }
    }

    private struct Connection {
        let row: Row
        /// Voor het tabblad Bronnen: de beschrijving met de stand erbij.
        let detail: String
    }

    private static func connections(config: AppConfig, bundle: Bundle, locale: Locale) -> [Connection] {
        let accounts = config.accounts.map { account in
            let summary = String(localized: "PR's, tags, repo's, manifesten en lockfiles van dit account", bundle: bundle, locale: locale,
                                 comment: "Wat Pullwatch bij de server van een account ophaalt")
            let detail = account.isPaused
                ? String(localized: "\(summary); dit account staat uit", bundle: bundle, locale: locale,
                         comment: "Beschrijving van de server van een account dat uitgezet is")
                : summary
            return Connection(row: Row(name: account.displayName, isOn: !account.isPaused, summary: summary, urls: [server(of: account)]),
                              detail: detail)
        }
        let gitHub = config.accounts.filter { $0.kind == .gitHub }
        var others: [Connection] = []

        // De device flow en het vernieuwen van het token gaan naar de GitHub App van
        // `GitHubAppConfig.main`, en die staat altijd op github.com, ook bij een Enterprise-account.
        let signingIn = gitHub.filter { $0.authMethod == .gitHubApp }
        if !signingIn.isEmpty {
            let summary = String(localized: "Inloggen met de GitHub App en het token daarvan vernieuwen", bundle: bundle, locale: locale,
                                 comment: "Wat Pullwatch bij het inloggen bij GitHub doet")
            others.append(Connection(
                row: Row(name: String(localized: "Inloggen bij GitHub", bundle: bundle, locale: locale, comment: "Verbinding in het overzicht van bronnen"),
                         isOn: signingIn.contains { !$0.isPaused }, summary: summary, urls: [URL(string: "https://github.com")!]),
                detail: summary))
        }

        // `<web>/<login>.png` (`Account.gitHubAvatarURL`) op de server van elk GitHub-account;
        // github.com stuurt door naar avatars.githubusercontent.com, waar ook de foto's staan die de API noemt.
        if !gitHub.isEmpty {
            var urls: [URL] = []
            for account in gitHub {
                let web = account.effectiveInstanceURL ?? URL(string: "https://github.com")!
                guard !urls.contains(web) else { continue }
                urls.append(web)
                if web.host() == "github.com" { urls.append(URL(string: "https://avatars.githubusercontent.com")!) }
            }
            let summary = String(localized: "Profielfoto's van je accounts en van de auteurs van PR's en tags", bundle: bundle, locale: locale,
                                 comment: "Wat Pullwatch voor de profielfoto's ophaalt")
            others.append(Connection(
                row: Row(name: String(localized: "Profielfoto's", bundle: bundle, locale: locale, comment: "Verbinding in het overzicht van bronnen"),
                         isOn: gitHub.contains { !$0.isPaused }, summary: summary, urls: urls),
                detail: summary))
        }

        let summary = String(localized: "Zoekt naar een nieuwe versie van Pullwatch en haalt de updates op", bundle: bundle, locale: locale,
                             comment: "Updatecheck: de releases op api.github.com, de appcast en downloads op github.com")
        let detail = config.checkForUpdates
            ? String(localized: "\(summary); Automatisch op updates controleren staat aan", bundle: bundle, locale: locale,
                     comment: "Beschrijving van de updatecheck met de stand van de instelling in Algemeen")
            : String(localized: "\(summary); Automatisch op updates controleren staat uit", bundle: bundle, locale: locale,
                     comment: "Beschrijving van de updatecheck met de stand van de instelling in Algemeen")
        others.append(Connection(
            row: Row(name: String(localized: "Updatecheck van Pullwatch", bundle: bundle, locale: locale, comment: "Verbinding in het overzicht van bronnen"),
                     isOn: config.checkForUpdates, summary: summary,
                     urls: [URL(string: "https://api.github.com")!, URL(string: "https://github.com")!]),
            detail: detail))
        return accounts + others
    }

    /// De teksten van PullwatchCore in de taal van `locale`, als de bundle die heeft; anders in de
    /// taal van de app.
    private static func bundle(for locale: Locale) -> Bundle {
        let own = Bundle.core(for: locale.language.languageCode?.identifier)
        return own.bundleURL.pathExtension == "lproj" ? own : .localizedCore
    }

    /// Een `LocalizedStringResource` uit de catalogus (zonder argumenten, zoals de beschrijvingen
    /// van de bronnen) in `bundle`; de bundle van zo'n resource kun je niet vervangen, dus op sleutel.
    private static func resolve(_ resource: LocalizedStringResource, bundle: Bundle, locale: Locale) -> String {
        bundle.localizedString(forKey: resource.key, value: String(localized: resource), table: resource.table)
    }
}
